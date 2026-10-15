<?php
require_once __DIR__ . '/config.php';

// Mapea el rol_codigo real del ERP al rol simplificado que usa este backend.
// Ajusta esta lista si en el ERP los códigos de rol son otros — se ve con
// SELECT DISTINCT rol_codigo FROM usuarios en la base del ERP.
function mapearRolErp(string $rolErp): string {
    return match (strtoupper($rolErp)) {
        'SUPERVISOR', 'ADMIN' => 'admin',
        'VENTAS' => 'vendedor',
        'ALMACENERO' => 'almacen',
        default => 'vendedor', // cualquier empleado puede mandar requerimientos
    };
}

// Valida el header Authorization: Bearer <token> contra la tabla sesiones.
// Nunca confía en nada que mande el celular aparte del token — el usuario y
// el rol siempre se leen de la base, recién validados acá.
function usuarioAutenticado(): array {
    $headers = getallheaders();
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (!str_starts_with($auth, 'Bearer ')) {
        responderError('AUTH_INVALID', 'Falta el token de autenticación', 401);
    }
    $token = substr($auth, 7);

    $stmt = db()->prepare(
        'SELECT u.id, u.usuario, u.nombre, u.rol
         FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id
         WHERE s.token = ? AND s.expira_en > NOW()'
    );
    $stmt->execute([$token]);
    $row = $stmt->fetch();
    if (!$row) {
        responderError('AUTH_INVALID', 'Token inválido o expirado', 401);
    }
    return $row; // ['id' => ..., 'usuario' => ..., 'nombre' => ..., 'rol' => ...]
}

// Exige que el usuario autenticado tenga uno de los roles dados. Se llama
// DESPUÉS de usuarioAutenticado() en cada acción que lo necesite — nunca se
// confía en lo que el cliente dice que puede hacer, siempre se revalida acá.
function exigirRol(array $usuario, array $rolesPermitidos): void {
    if (!in_array($usuario['rol'], $rolesPermitidos, true)) {
        responderError('FORBIDDEN', 'Tu rol (' . $usuario['rol'] . ') no puede hacer esta acción', 403);
    }
}
