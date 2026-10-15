<?php
// Lista base de materiales y herramientas (lo que aparece al armar un
// requerimiento o un checklist) — se edita desde Configuración, solo admin.
//   GET  checklist_catalogo.php?tipo=materiales   -> listar (o sin ?tipo, todo)
//   POST checklist_catalogo.php                   -> crear   (admin)
//   POST checklist_catalogo.php?accion=editar&id=5 -> editar  (admin)
//   POST checklist_catalogo.php?accion=eliminar&id=5 -> desactivar (admin, no se borra la fila)
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';
require_once __DIR__ . '/bitacora_helper.php';

$usuario = usuarioAutenticado();
$pdo = db();
$metodo = $_SERVER['REQUEST_METHOD'];
$accion = $_GET['accion'] ?? null;

if ($metodo === 'GET') {
    $tipo = $_GET['tipo'] ?? null;
    if ($tipo) {
        $stmt = $pdo->prepare('SELECT * FROM checklist_catalogo WHERE activo = 1 AND tipo = ? ORDER BY orden');
        $stmt->execute([$tipo]);
    } else {
        $stmt = $pdo->query('SELECT * FROM checklist_catalogo WHERE activo = 1 ORDER BY tipo, orden');
    }
    responder(['items' => $stmt->fetchAll()]);
}

if ($metodo !== 'POST') responderError('METHOD_NOT_ALLOWED', 'Usa GET o POST', 405);
exigirRol($usuario, ['admin']); // toda escritura de la lista base es de configuración
$body = cuerpoJson();

if (!$accion) {
    $tipo = $body['tipo'] ?? '';
    $nombre = trim($body['nombre'] ?? '');
    if (!in_array($tipo, ['materiales', 'herramientas'], true) || $nombre === '') {
        responderError('SCHEMA_INVALID', 'tipo (materiales|herramientas) y nombre son obligatorios', 400);
    }
    $stmt = $pdo->prepare(
        'INSERT INTO checklist_catalogo (tipo, categoria, nombre, unidad, precio, orden, base) VALUES (?, ?, ?, ?, ?, ?, 0)'
    );
    $stmt->execute([$tipo, $body['categoria'] ?? '', $nombre, $body['unidad'] ?? null, $body['precio'] ?? null, $body['orden'] ?? 0]);
    $id = (int) $pdo->lastInsertId();
    registrarBitacora($usuario['id'], 'crear', 'checklist_catalogo', $id, ['nombre' => $nombre]);
    responder(['id' => $id]);
}

$id = (int) ($_GET['id'] ?? 0);
if (!$id) responderError('SCHEMA_INVALID', 'Falta ?id=', 400);

if ($accion === 'editar') {
    $stmt = $pdo->prepare('UPDATE checklist_catalogo SET categoria=?, nombre=?, unidad=?, precio=?, orden=? WHERE id = ?');
    $stmt->execute([$body['categoria'] ?? '', $body['nombre'] ?? '', $body['unidad'] ?? null, $body['precio'] ?? null, $body['orden'] ?? 0, $id]);
    if ($stmt->rowCount() === 0) responderError('NOT_FOUND', 'No existe ese ítem del catálogo', 404);
    registrarBitacora($usuario['id'], 'editar', 'checklist_catalogo', $id, null);
    responder(['ok' => true]);
}

if ($accion === 'eliminar') {
    $pdo->prepare('UPDATE checklist_catalogo SET activo = 0 WHERE id = ?')->execute([$id]);
    registrarBitacora($usuario['id'], 'eliminar', 'checklist_catalogo', $id, null);
    responder(['ok' => true]);
}

responderError('ACCION_INVALIDA', "Acción '$accion' no reconocida", 400);
