<?php
// Salidas de herramientas (checklist o maleta):
//   GET  checklists_herramientas.php                 -> listar
//   GET  checklists_herramientas.php?codigo=HER-0001 -> detalle (con items)
//   POST checklists_herramientas.php                 -> crear ("registrado", cualquier empleado)
//   POST ?accion=confirmar_salida&codigo=HER-0001     -> almacén marca salio=1/0 por herramienta
//   POST ?accion=confirmar_devolucion&codigo=HER-0001 -> almacén marca volvio=1/0 por herramienta
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';
require_once __DIR__ . '/bitacora_helper.php';

$usuario = usuarioAutenticado();
$pdo = db();

function cargarHerramientas(PDO $pdo, string $codigo): ?array {
    $stmt = $pdo->prepare('SELECT * FROM checklists_herramientas WHERE numero = ?');
    $stmt->execute([$codigo]);
    $h = $stmt->fetch();
    if (!$h) return null;
    $items = $pdo->prepare('SELECT * FROM checklist_herramientas_items WHERE checklist_id = ? ORDER BY orden');
    $items->execute([$h['id']]);
    $h['items'] = $items->fetchAll();
    return $h;
}

$metodo = $_SERVER['REQUEST_METHOD'];
$accion = $_GET['accion'] ?? null;
$codigo = $_GET['codigo'] ?? null;

if ($metodo === 'GET') {
    if ($codigo) {
        $h = cargarHerramientas($pdo, $codigo);
        if (!$h) responderError('NOT_FOUND', "La salida '$codigo' no existe", 404);
        responder($h);
    }
    $stmt = $pdo->query('SELECT * FROM checklists_herramientas ORDER BY fecha_registro DESC LIMIT 200');
    responder(['items' => $stmt->fetchAll()]);
}

if ($metodo !== 'POST') responderError('METHOD_NOT_ALLOWED', 'Usa GET o POST', 405);
$body = cuerpoJson();

// --------------------------------------------------------------- crear ---
if (!$accion) {
    $obra = trim($body['obra'] ?? '');
    $responsable = trim($body['responsable'] ?? '');
    $items = $body['items'] ?? [];
    if ($obra === '' || $responsable === '' || empty($items)) {
        responderError('SCHEMA_INVALID', 'obra, responsable y al menos un item son obligatorios', 400);
    }

    $pdo->beginTransaction();
    try {
        $numero = siguienteNumero('herramientas', 'HER');
        $pdo->prepare(
            'INSERT INTO checklists_herramientas (numero, obra, responsable, maleta_id, maleta_nombre, observaciones, fecha_registro, creado_por)
             VALUES (?, ?, ?, ?, ?, ?, NOW(), ?)'
        )->execute([
            $numero, $obra, $responsable, $body['maleta_id'] ?? null, $body['maleta_nombre'] ?? null,
            $body['observaciones'] ?? null, $usuario['id'],
        ]);
        $checklistId = (int) $pdo->lastInsertId();

        $stmtItem = $pdo->prepare(
            'INSERT INTO checklist_herramientas_items (checklist_id, orden, categoria, nombre, cantidad, unidad, imagen, es_extra, es_producto)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        foreach ($items as $i => $item) {
            $stmtItem->execute([
                $checklistId, $i, $item['categoria'] ?? '', $item['nombre'] ?? '', (int) ($item['cantidad'] ?? 1),
                $item['unidad'] ?? null, $item['imagen'] ?? null, !empty($item['es_extra']) ? 1 : 0, !empty($item['es_producto']) ? 1 : 0,
            ]);
        }
        registrarBitacora($usuario['id'], 'crear', 'checklists_herramientas', $checklistId, ['numero' => $numero, 'obra' => $obra]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        responderError('SERVER_ERROR', 'No se pudo registrar la salida', 500);
    }
    responder(cargarHerramientas($pdo, $numero));
}

// A partir de acá, acciones sobre una salida existente.
if (!$codigo) responderError('SCHEMA_INVALID', 'Falta ?codigo=', 400);
$h = cargarHerramientas($pdo, $codigo);
if (!$h) responderError('NOT_FOUND', "La salida '$codigo' no existe", 404);

// Marca salio/volvio ítem por ítem según $campo, y cuenta cuántos quedaron
// en false explícito (faltantes) para dejarlo en la respuesta.
function marcarItems(PDO $pdo, int $checklistId, array $marcas, string $campo): int {
    $stmt = $pdo->prepare("UPDATE checklist_herramientas_items SET $campo = ? WHERE id = ? AND checklist_id = ?");
    $faltantes = 0;
    foreach ($marcas as $marca) {
        $valor = !empty($marca['valor']) ? 1 : 0;
        if (!$valor) $faltantes++;
        $stmt->execute([$valor, (int) $marca['item_id'], $checklistId]);
    }
    return $faltantes;
}

// ------------------------------------------------------ confirmar_salida -
if ($accion === 'confirmar_salida') {
    exigirRol($usuario, ['almacen']);
    if ($h['estado'] !== 'registrado') {
        responderError('ESTADO_INVALIDO', 'Solo se confirma la salida de un registro recién creado', 409);
    }
    $marcas = $body['items'] ?? [];
    if (empty($marcas)) responderError('SCHEMA_INVALID', 'Falta items: [{item_id, valor}]', 400);

    $pdo->beginTransaction();
    try {
        $faltantes = marcarItems($pdo, $h['id'], $marcas, 'salio');
        $pdo->prepare(
            "UPDATE checklists_herramientas SET estado = 'pendiente', fecha_confirmacion_salida = NOW(), salida_confirmada_por = ?, version = version + 1 WHERE id = ?"
        )->execute([$usuario['nombre'], $h['id']]);
        registrarBitacora($usuario['id'], 'confirmar_salida', 'checklists_herramientas', $h['id'], ['numero' => $codigo, 'faltantes' => $faltantes]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        responderError('SERVER_ERROR', 'No se pudo confirmar la salida', 500);
    }
    responder(cargarHerramientas($pdo, $codigo));
}

// -------------------------------------------------- confirmar_devolucion -
if ($accion === 'confirmar_devolucion') {
    exigirRol($usuario, ['almacen']);
    if ($h['estado'] !== 'pendiente') {
        responderError('ESTADO_INVALIDO', 'Solo se confirma devolución de una salida pendiente', 409);
    }
    $marcas = $body['items'] ?? [];
    if (empty($marcas)) responderError('SCHEMA_INVALID', 'Falta items: [{item_id, valor}]', 400);

    $pdo->beginTransaction();
    try {
        $faltantes = marcarItems($pdo, $h['id'], $marcas, 'volvio');
        $pdo->prepare(
            "UPDATE checklists_herramientas SET estado = 'conforme', fecha_devolucion = NOW(), encargado = ?, observaciones_devolucion = ?, version = version + 1 WHERE id = ?"
        )->execute([$usuario['nombre'], $body['observaciones_devolucion'] ?? null, $h['id']]);
        registrarBitacora($usuario['id'], 'confirmar_devolucion', 'checklists_herramientas', $h['id'], ['numero' => $codigo, 'faltantes' => $faltantes]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        responderError('SERVER_ERROR', 'No se pudo confirmar la devolución', 500);
    }
    responder(cargarHerramientas($pdo, $codigo));
}

responderError('ACCION_INVALIDA', "Acción '$accion' no reconocida", 400);
