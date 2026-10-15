<?php
// Maletas de herramientas ya armadas, con sus niveles:
//   GET  maletas.php                         -> listar todas con sus items
//   POST maletas.php                         -> crear maleta             (admin)
//   POST maletas.php?accion=agregar_item&maleta_id=1  -> agregar un item (admin)
//   POST maletas.php?accion=eliminar_item&item_id=5   -> quitar un item  (admin)
//   POST maletas.php?accion=eliminar&id=1    -> desactivar la maleta     (admin)
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';
require_once __DIR__ . '/bitacora_helper.php';

$usuario = usuarioAutenticado();
$pdo = db();
$metodo = $_SERVER['REQUEST_METHOD'];
$accion = $_GET['accion'] ?? null;

if ($metodo === 'GET') {
    $maletas = $pdo->query('SELECT * FROM maletas WHERE activo = 1 ORDER BY orden')->fetchAll();
    $stmtItems = $pdo->prepare('SELECT * FROM maleta_items WHERE maleta_id = ? ORDER BY orden');
    foreach ($maletas as &$m) {
        $stmtItems->execute([$m['id']]);
        $m['items'] = $stmtItems->fetchAll();
    }
    responder(['items' => $maletas]);
}

if ($metodo !== 'POST') responderError('METHOD_NOT_ALLOWED', 'Usa GET o POST', 405);
exigirRol($usuario, ['admin']);
$body = cuerpoJson();

if (!$accion) {
    $nombre = trim($body['nombre'] ?? '');
    if ($nombre === '') responderError('SCHEMA_INVALID', 'nombre es obligatorio', 400);
    $stmt = $pdo->prepare('INSERT INTO maletas (nombre, orden) VALUES (?, ?)');
    $stmt->execute([$nombre, $body['orden'] ?? 0]);
    $id = (int) $pdo->lastInsertId();
    registrarBitacora($usuario['id'], 'crear', 'maletas', $id, ['nombre' => $nombre]);
    responder(['id' => $id]);
}

if ($accion === 'agregar_item') {
    $maletaId = (int) ($_GET['maleta_id'] ?? 0);
    $nombre = trim($body['nombre'] ?? '');
    $nivel = trim($body['nivel'] ?? '');
    if (!$maletaId || $nombre === '' || $nivel === '') {
        responderError('SCHEMA_INVALID', 'maleta_id, nivel y nombre son obligatorios', 400);
    }
    $stmt = $pdo->prepare('INSERT INTO maleta_items (maleta_id, nivel, nombre, imagen, orden) VALUES (?, ?, ?, ?, ?)');
    $stmt->execute([$maletaId, $nivel, $nombre, $body['imagen'] ?? null, $body['orden'] ?? 0]);
    $id = (int) $pdo->lastInsertId();
    registrarBitacora($usuario['id'], 'agregar_item', 'maleta_items', $id, ['maleta_id' => $maletaId, 'nombre' => $nombre]);
    responder(['id' => $id]);
}

if ($accion === 'eliminar_item') {
    $itemId = (int) ($_GET['item_id'] ?? 0);
    if (!$itemId) responderError('SCHEMA_INVALID', 'Falta ?item_id=', 400);
    $pdo->prepare('DELETE FROM maleta_items WHERE id = ?')->execute([$itemId]);
    registrarBitacora($usuario['id'], 'eliminar_item', 'maleta_items', $itemId, null);
    responder(['ok' => true]);
}

if ($accion === 'eliminar') {
    $id = (int) ($_GET['id'] ?? 0);
    if (!$id) responderError('SCHEMA_INVALID', 'Falta ?id=', 400);
    $pdo->prepare('UPDATE maletas SET activo = 0 WHERE id = ?')->execute([$id]);
    registrarBitacora($usuario['id'], 'eliminar', 'maletas', $id, null);
    responder(['ok' => true]);
}

responderError('ACCION_INVALIDA', "Acción '$accion' no reconocida", 400);
