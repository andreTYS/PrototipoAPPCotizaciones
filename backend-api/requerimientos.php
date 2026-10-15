<?php
// Requerimientos de materiales — los 4 estados, cada uno con su rol:
//   GET  requerimientos.php                 -> listar
//   GET  requerimientos.php?codigo=REQ-0001 -> detalle (con items)
//   POST requerimientos.php                 -> crear               (cualquier empleado)
//   POST requerimientos.php?accion=aprobar&codigo=REQ-0001          (encargado: admin)
//   POST requerimientos.php?accion=alistar_item&codigo=...&item_id=.. (almacenero)
//   POST requerimientos.php?accion=listo&codigo=REQ-0001            (almacenero)
//   POST requerimientos.php?accion=entregar&codigo=REQ-0001         (empleado que confirma recepción)
//
// Todas las acciones de escritura mandan "version" en el body: si no
// coincide con la que está en la base, significa que otro dispositivo lo
// cambió primero -> 409 CONFLICT, nunca se pisa en silencio.
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';
require_once __DIR__ . '/bitacora_helper.php';

$usuario = usuarioAutenticado(); // exige sesión válida en TODAS las acciones
$pdo = db();

function cargarRequerimiento(PDO $pdo, string $codigo): ?array {
    $stmt = $pdo->prepare('SELECT * FROM requerimientos WHERE numero = ?');
    $stmt->execute([$codigo]);
    $req = $stmt->fetch();
    if (!$req) return null;
    $items = $pdo->prepare('SELECT * FROM requerimiento_items WHERE requerimiento_id = ? ORDER BY orden');
    $items->execute([$req['id']]);
    $req['items'] = $items->fetchAll();
    return $req;
}

// Actualiza con control de versión optimista. Devuelve false si la versión
// no coincidía (alguien más lo cambió primero) en vez de pisarlo.
function actualizarConVersion(PDO $pdo, int $id, int $versionEsperada, array $campos): bool {
    $sets = [];
    $valores = [];
    foreach ($campos as $col => $val) {
        $sets[] = "$col = ?";
        $valores[] = $val;
    }
    $sets[] = 'version = version + 1';
    $valores[] = $id;
    $valores[] = $versionEsperada;
    $sql = 'UPDATE requerimientos SET ' . implode(', ', $sets) . ' WHERE id = ? AND version = ?';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($valores);
    return $stmt->rowCount() === 1;
}

$metodo = $_SERVER['REQUEST_METHOD'];
$accion = $_GET['accion'] ?? null;
$codigo = $_GET['codigo'] ?? null;

// ---------------------------------------------------------------- GET ----
if ($metodo === 'GET') {
    if ($codigo) {
        $req = cargarRequerimiento($pdo, $codigo);
        if (!$req) responderError('NOT_FOUND', "El requerimiento '$codigo' no existe", 404);
        responder($req);
    }
    $estado = $_GET['estado'] ?? null;
    if ($estado) {
        $stmt = $pdo->prepare('SELECT * FROM requerimientos WHERE estado = ? ORDER BY fecha_creacion DESC');
        $stmt->execute([$estado]);
    } else {
        $stmt = $pdo->query('SELECT * FROM requerimientos ORDER BY fecha_creacion DESC LIMIT 200');
    }
    responder(['items' => $stmt->fetchAll()]);
}

if ($metodo !== 'POST') {
    responderError('METHOD_NOT_ALLOWED', 'Usa GET o POST', 405);
}

$body = cuerpoJson();

// ------------------------------------------------- POST: crear nuevo -----
if (!$accion) {
    // Cualquier empleado autenticado puede mandar un requerimiento.
    $obra = trim($body['obra'] ?? '');
    $solicitante = trim($body['solicitante'] ?? $usuario['nombre']);
    $urgente = !empty($body['urgente']) ? 1 : 0;
    $observaciones = $body['observaciones'] ?? null;
    $items = $body['items'] ?? [];
    if ($obra === '' || empty($items)) {
        responderError('SCHEMA_INVALID', 'obra y al menos un item son obligatorios', 400);
    }

    $pdo->beginTransaction();
    try {
        $numero = siguienteNumero('requerimiento', 'REQ');
        $pdo->prepare(
            'INSERT INTO requerimientos (numero, obra, solicitante, urgente, observaciones, fecha_creacion, creado_por)
             VALUES (?, ?, ?, ?, ?, NOW(), ?)'
        )->execute([$numero, $obra, $solicitante, $urgente, $observaciones, $usuario['id']]);
        $requerimientoId = (int) $pdo->lastInsertId();

        $stmtItem = $pdo->prepare(
            'INSERT INTO requerimiento_items (requerimiento_id, orden, categoria, nombre, cantidad, unidad, precio_unitario, es_extra, es_producto)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        foreach ($items as $i => $item) {
            $stmtItem->execute([
                $requerimientoId, $i, $item['categoria'] ?? '', $item['nombre'] ?? '',
                (int) ($item['cantidad'] ?? 1), $item['unidad'] ?? null, $item['precio_unitario'] ?? null,
                !empty($item['es_extra']) ? 1 : 0, !empty($item['es_producto']) ? 1 : 0,
            ]);
        }
        registrarBitacora($usuario['id'], 'crear', 'requerimientos', $requerimientoId, ['numero' => $numero, 'obra' => $obra]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        responderError('SERVER_ERROR', 'No se pudo crear el requerimiento', 500);
    }
    responder(cargarRequerimiento($pdo, $numero));
}

// A partir de acá todas las acciones son sobre un requerimiento existente.
if (!$codigo) responderError('SCHEMA_INVALID', 'Falta ?codigo=', 400);
$req = cargarRequerimiento($pdo, $codigo);
if (!$req) responderError('NOT_FOUND', "El requerimiento '$codigo' no existe", 404);

$versionRecibida = (int) ($body['version'] ?? -1);

// --------------------------------------------------- POST: aprobar -------
if ($accion === 'aprobar') {
    exigirRol($usuario, ['admin']); // "encargado" — ajusta el rol si tienen uno propio para jefe de obra
    if ($req['estado'] !== 'pendiente') {
        responderError('ESTADO_INVALIDO', 'Solo se puede aprobar un requerimiento pendiente', 409);
    }
    $ok = actualizarConVersion($pdo, $req['id'], $versionRecibida, [
        'estado' => 'aprobado', 'fecha_aprobacion' => date('Y-m-d H:i:s'), 'aprobado_por' => $usuario['nombre'],
    ]);
    if (!$ok) responderError('CONFLICTO_VERSION', 'Alguien más ya actualizó este requerimiento, revisa de nuevo', 409);
    registrarBitacora($usuario['id'], 'aprobar', 'requerimientos', $req['id'], ['numero' => $codigo]);
    responder(cargarRequerimiento($pdo, $codigo));
}

// ------------------------------------------ POST: alistar un material ----
if ($accion === 'alistar_item') {
    exigirRol($usuario, ['almacen']);
    $itemId = (int) ($_GET['item_id'] ?? 0);
    if (!$itemId) responderError('SCHEMA_INVALID', 'Falta ?item_id=', 400);
    if ($req['estado'] !== 'aprobado') {
        responderError('ESTADO_INVALIDO', 'Solo se alista un requerimiento ya aprobado', 409);
    }
    $stmt = $pdo->prepare('UPDATE requerimiento_items SET alistado = 1, alistado_por = ?, fecha_alistado = NOW() WHERE id = ? AND requerimiento_id = ?');
    $stmt->execute([$usuario['nombre'], $itemId, $req['id']]);
    if ($stmt->rowCount() === 0) responderError('NOT_FOUND', 'Ese ítem no pertenece a este requerimiento', 404);
    registrarBitacora($usuario['id'], 'alistar_item', 'requerimiento_items', $itemId, ['requerimiento' => $codigo]);
    responder(cargarRequerimiento($pdo, $codigo));
}

// ------------------------------------- POST: listo para entrega ----------
if ($accion === 'listo') {
    exigirRol($usuario, ['almacen']);
    if ($req['estado'] !== 'aprobado') {
        responderError('ESTADO_INVALIDO', 'Solo pasa a "listo" un requerimiento aprobado', 409);
    }
    $sinAlistar = array_filter($req['items'], fn($i) => !$i['alistado']);
    if (count($sinAlistar) > 0) {
        responderError('ITEMS_PENDIENTES', 'Todavía hay materiales sin alistar', 409);
    }
    $ok = actualizarConVersion($pdo, $req['id'], $versionRecibida, [
        'estado' => 'listo', 'fecha_listo' => date('Y-m-d H:i:s'), 'alistado_por' => $usuario['nombre'],
    ]);
    if (!$ok) responderError('CONFLICTO_VERSION', 'Alguien más ya actualizó este requerimiento, revisa de nuevo', 409);
    registrarBitacora($usuario['id'], 'listo', 'requerimientos', $req['id'], ['numero' => $codigo]);
    responder(cargarRequerimiento($pdo, $codigo));
}

// ----------------------------- POST: confirmar recepción (entregar) ------
if ($accion === 'entregar') {
    // Cualquier empleado puede confirmar que lo recibió — no se restringe a
    // un rol específico, pero sí queda su nombre real en recibido_por.
    if ($req['estado'] !== 'listo') {
        responderError('ESTADO_INVALIDO', 'Solo se entrega un requerimiento ya listo', 409);
    }
    $ok = actualizarConVersion($pdo, $req['id'], $versionRecibida, [
        'estado' => 'entregado', 'fecha_entrega' => date('Y-m-d H:i:s'), 'recibido_por' => $usuario['nombre'],
    ]);
    if (!$ok) responderError('CONFLICTO_VERSION', 'Alguien más ya actualizó este requerimiento, revisa de nuevo', 409);
    registrarBitacora($usuario['id'], 'entregar', 'requerimientos', $req['id'], ['numero' => $codigo]);
    responder(cargarRequerimiento($pdo, $codigo));
}

responderError('ACCION_INVALIDA', "Acción '$accion' no reconocida", 400);
