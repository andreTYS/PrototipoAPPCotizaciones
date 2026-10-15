<?php
// Cotizaciones:
//   GET  cotizaciones.php                   -> listar
//   GET  cotizaciones.php?codigo=S00001     -> detalle (con items)
//   POST cotizaciones.php                   -> crear               (cualquier vendedor)
//   POST cotizaciones.php?accion=editar&codigo=S00001  -> editar cabecera+items (creador o admin)
//
// Igual que requerimientos.php: "version" en el body protege de que dos
// dispositivos editen la misma cotización a la vez sin darse cuenta.
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';
require_once __DIR__ . '/bitacora_helper.php';

$usuario = usuarioAutenticado();
$pdo = db();

function cargarCotizacion(PDO $pdo, string $codigo): ?array {
    $stmt = $pdo->prepare('SELECT * FROM cotizaciones WHERE numero = ?');
    $stmt->execute([$codigo]);
    $cot = $stmt->fetch();
    if (!$cot) return null;
    $items = $pdo->prepare('SELECT * FROM cotizacion_items WHERE cotizacion_id = ? ORDER BY orden');
    $items->execute([$cot['id']]);
    $cot['items'] = $items->fetchAll();
    return $cot;
}

$metodo = $_SERVER['REQUEST_METHOD'];
$accion = $_GET['accion'] ?? null;
$codigo = $_GET['codigo'] ?? null;

if ($metodo === 'GET') {
    if ($codigo) {
        $cot = cargarCotizacion($pdo, $codigo);
        if (!$cot) responderError('NOT_FOUND', "La cotización '$codigo' no existe", 404);
        responder($cot);
    }
    $stmt = $pdo->query('SELECT * FROM cotizaciones ORDER BY fecha DESC LIMIT 200');
    responder(['items' => $stmt->fetchAll()]);
}

if ($metodo !== 'POST') responderError('METHOD_NOT_ALLOWED', 'Usa GET o POST', 405);
$body = cuerpoJson();

function guardarItems(PDO $pdo, int $cotizacionId, array $items): void {
    $pdo->prepare('DELETE FROM cotizacion_items WHERE cotizacion_id = ?')->execute([$cotizacionId]);
    $stmt = $pdo->prepare(
        'INSERT INTO cotizacion_items (cotizacion_id, orden, producto_id, nombre, referencia_interna, cantidad, precio_unitario, unidad_medida, imagen, agregado_en_edicion)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($items as $i => $item) {
        $stmt->execute([
            $cotizacionId, $i, $item['producto_id'] ?? null, $item['nombre'] ?? '', $item['referencia_interna'] ?? null,
            (float) ($item['cantidad'] ?? 0), (float) ($item['precio_unitario'] ?? 0), $item['unidad_medida'] ?? null,
            $item['imagen'] ?? null, !empty($item['agregado_en_edicion']) ? 1 : 0,
        ]);
    }
}

// --------------------------------------------------------------- crear ---
if (!$accion) {
    $cliente = trim($body['cliente'] ?? '');
    $items = $body['items'] ?? [];
    if ($cliente === '' || empty($items)) {
        responderError('SCHEMA_INVALID', 'cliente y al menos un item son obligatorios', 400);
    }
    $total = array_reduce($items, fn($s, $i) => $s + ((float) ($i['cantidad'] ?? 0) * (float) ($i['precio_unitario'] ?? 0)), 0.0);

    $pdo->beginTransaction();
    try {
        $numero = siguienteNumero('cotizacion', 'S', 5, '');
        $pdo->prepare(
            'INSERT INTO cotizaciones (numero, cliente, ruc_dni, telefono, vendedor, banco, moneda, nro_cuenta, cci, total, fecha, creado_por)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?)'
        )->execute([
            $numero, $cliente, $body['ruc_dni'] ?? null, $body['telefono'] ?? null, $usuario['nombre'],
            $body['banco'] ?? null, $body['moneda'] ?? null, $body['nro_cuenta'] ?? null, $body['cci'] ?? null,
            $total, $usuario['id'],
        ]);
        $cotizacionId = (int) $pdo->lastInsertId();
        guardarItems($pdo, $cotizacionId, $items);
        registrarBitacora($usuario['id'], 'crear', 'cotizaciones', $cotizacionId, ['numero' => $numero, 'cliente' => $cliente]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        responderError('SERVER_ERROR', 'No se pudo crear la cotización', 500);
    }
    responder(cargarCotizacion($pdo, $numero));
}

// A partir de acá, acciones sobre una cotización existente.
if (!$codigo) responderError('SCHEMA_INVALID', 'Falta ?codigo=', 400);
$cot = cargarCotizacion($pdo, $codigo);
if (!$cot) responderError('NOT_FOUND', "La cotización '$codigo' no existe", 404);

// -------------------------------------------------------------- editar ---
if ($accion === 'editar') {
    // Puede editar quien la creó, o un admin — así un compañero no borra el
    // trabajo de otro sin querer, pero el encargado siempre puede corregir.
    if ($cot['creado_por'] != $usuario['id']) {
        exigirRol($usuario, ['admin']);
    }
    $versionRecibida = (int) ($body['version'] ?? -1);
    $items = $body['items'] ?? $cot['items'];
    $total = array_reduce($items, fn($s, $i) => $s + ((float) ($i['cantidad'] ?? 0) * (float) ($i['precio_unitario'] ?? 0)), 0.0);

    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare(
            'UPDATE cotizaciones SET cliente=?, ruc_dni=?, telefono=?, banco=?, moneda=?, nro_cuenta=?, cci=?, total=?,
             version = version + 1, editado_en = NOW(), editado_por = ?
             WHERE id = ? AND version = ?'
        );
        $stmt->execute([
            $body['cliente'] ?? $cot['cliente'], $body['ruc_dni'] ?? $cot['ruc_dni'], $body['telefono'] ?? $cot['telefono'],
            $body['banco'] ?? $cot['banco'], $body['moneda'] ?? $cot['moneda'], $body['nro_cuenta'] ?? $cot['nro_cuenta'],
            $body['cci'] ?? $cot['cci'], $total, $usuario['nombre'], $cot['id'], $versionRecibida,
        ]);
        if ($stmt->rowCount() !== 1) {
            $pdo->rollBack();
            responderError('CONFLICTO_VERSION', 'Alguien más ya editó esta cotización, revisa de nuevo', 409);
        }
        guardarItems($pdo, $cot['id'], $items);
        registrarBitacora($usuario['id'], 'editar', 'cotizaciones', $cot['id'], ['numero' => $codigo]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        responderError('SERVER_ERROR', 'No se pudo editar la cotización', 500);
    }
    responder(cargarCotizacion($pdo, $codigo));
}

responderError('ACCION_INVALIDA', "Acción '$accion' no reconocida", 400);
