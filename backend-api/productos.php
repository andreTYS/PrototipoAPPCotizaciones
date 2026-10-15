<?php
// Catálogo de productos para cotizar:
//   GET  productos.php?q=panel   -> buscar (todos los autenticados)
//   GET  productos.php           -> listar (paginado, 100 por página)
//   POST productos.php           -> crear producto "local"   (admin)
//   POST productos.php?accion=editar&id=5 -> editar           (admin)
//   POST productos.php?accion=eliminar&id=5 -> desactivar      (admin)
//
// Los productos con origen="erp" los trae la sincronización con el ERP (no
// se crean a mano acá); origen="local" es lo que el admin agrega solo para
// el Cotizador.
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';
require_once __DIR__ . '/bitacora_helper.php';

$usuario = usuarioAutenticado();
$pdo = db();
$metodo = $_SERVER['REQUEST_METHOD'];
$accion = $_GET['accion'] ?? null;

if ($metodo === 'GET') {
    $q = trim($_GET['q'] ?? '');
    if ($q !== '') {
        $stmt = $pdo->prepare('SELECT * FROM productos WHERE activo = 1 AND (nombre LIKE ? OR referencia_interna LIKE ?) ORDER BY nombre LIMIT 100');
        $like = "%$q%";
        $stmt->execute([$like, $like]);
    } else {
        $pagina = max(1, (int) ($_GET['page'] ?? 1));
        $stmt = $pdo->prepare('SELECT * FROM productos WHERE activo = 1 ORDER BY nombre LIMIT 100 OFFSET ?');
        $stmt->execute([($pagina - 1) * 100]);
    }
    responder(['items' => $stmt->fetchAll()]);
}

if ($metodo !== 'POST') responderError('METHOD_NOT_ALLOWED', 'Usa GET o POST', 405);
exigirRol($usuario, ['admin']);
$body = cuerpoJson();

if (!$accion) {
    $nombre = trim($body['nombre'] ?? '');
    $categoria = trim($body['categoria'] ?? '');
    if ($nombre === '' || $categoria === '') responderError('SCHEMA_INVALID', 'nombre y categoria son obligatorios', 400);
    $stmt = $pdo->prepare(
        "INSERT INTO productos (nombre, categoria, precio_venta, costo, referencia_interna, unidad_medida, imagen, origen, creado_por)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'local', ?)"
    );
    $stmt->execute([
        $nombre, $categoria, $body['precio_venta'] ?? null, $body['costo'] ?? null,
        $body['referencia_interna'] ?? null, $body['unidad_medida'] ?? null, $body['imagen'] ?? null, $usuario['id'],
    ]);
    $id = (int) $pdo->lastInsertId();
    registrarBitacora($usuario['id'], 'crear', 'productos', $id, ['nombre' => $nombre]);
    responder(['id' => $id]);
}

$id = (int) ($_GET['id'] ?? 0);
if (!$id) responderError('SCHEMA_INVALID', 'Falta ?id=', 400);

if ($accion === 'editar') {
    $stmt = $pdo->prepare('UPDATE productos SET nombre=?, categoria=?, precio_venta=?, costo=?, referencia_interna=?, unidad_medida=?, imagen=? WHERE id = ?');
    $stmt->execute([
        $body['nombre'] ?? '', $body['categoria'] ?? '', $body['precio_venta'] ?? null, $body['costo'] ?? null,
        $body['referencia_interna'] ?? null, $body['unidad_medida'] ?? null, $body['imagen'] ?? null, $id,
    ]);
    if ($stmt->rowCount() === 0) responderError('NOT_FOUND', 'No existe ese producto', 404);
    registrarBitacora($usuario['id'], 'editar', 'productos', $id, null);
    responder(['ok' => true]);
}

if ($accion === 'eliminar') {
    $pdo->prepare('UPDATE productos SET activo = 0 WHERE id = ?')->execute([$id]);
    registrarBitacora($usuario['id'], 'eliminar', 'productos', $id, null);
    responder(['ok' => true]);
}

responderError('ACCION_INVALIDA', "Acción '$accion' no reconocida", 400);
