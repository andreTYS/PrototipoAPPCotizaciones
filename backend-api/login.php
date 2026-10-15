<?php
// POST /login.php  { "email": "...", "password": "..." }
//
// No guarda ni compara ninguna clave propia: le pasa el email/clave al ERP
// (el mismo /api/auth/login que ya usan ICR-TIENDA y el ERP web) y solo si
// el ERP dice que sí, crea la sesión acá y espeja al usuario — necesario
// para las foreign keys de bitacora/creado_por, nunca para la contraseña.
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth_helper.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    responderError('METHOD_NOT_ALLOWED', 'Usa POST', 405);
}

$body = cuerpoJson();
$email = trim($body['email'] ?? '');
$password = (string) ($body['password'] ?? '');
if ($email === '' || $password === '') {
    responderError('SCHEMA_INVALID', 'email y password son obligatorios', 400);
}

// --- 1. Validar credenciales contra el ERP real ---
$ch = curl_init(ERP_API_URL . '/auth/login');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_POSTFIELDS => json_encode(['email' => $email, 'password' => $password]),
    CURLOPT_TIMEOUT => 10,
]);
$respuestaErp = curl_exec($ch);
$httpErp = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($respuestaErp === false) {
    responderError('ERP_UNREACHABLE', 'No se pudo conectar con el ERP, intenta de nuevo', 503);
}
$datosErp = json_decode($respuestaErp, true);
if ($httpErp !== 200 || !isset($datosErp['data']['user'])) {
    responderError('AUTH_INVALID', 'Correo o contraseña incorrectos', 401);
}

$usuarioErp = $datosErp['data']['user'];
$erpUsuarioId = (int) $usuarioErp['usuario_id'];
$nombre = (string) $usuarioErp['nombre_completo'];
$rol = mapearRolErp((string) ($usuarioErp['rol_codigo'] ?? ''));

// --- 2. Espejar el usuario localmente (upsert por el id real del ERP) ---
$pdo = db();
$pdo->prepare(
    "INSERT INTO usuarios (id, usuario, nombre, clave_hash, rol, activo)
     VALUES (?, ?, ?, '', ?, 1)
     ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, rol = EXCLUDED.rol, activo = 1"
)->execute([$erpUsuarioId, $email, $nombre, $rol]);

// --- 3. Crear la sesión ---
$token = bin2hex(random_bytes(32));
$dispositivo = substr($_SERVER['HTTP_USER_AGENT'] ?? 'desconocido', 0, 120);
$pdo->prepare(
    "INSERT INTO sesiones (token, usuario_id, dispositivo, expira_en) VALUES (?, ?, ?, NOW() + INTERVAL '30 days')"
)->execute([$token, $erpUsuarioId, $dispositivo]);

responder([
    'token' => $token,
    'usuario' => ['id' => $erpUsuarioId, 'nombre' => $nombre, 'rol' => $rol],
]);
