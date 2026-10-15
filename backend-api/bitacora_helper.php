<?php
require_once __DIR__ . '/config.php';

// Registra en bitacora quién hizo qué y cuándo — se llama en cada acción que
// crea, aprueba, alista o entrega algo. $detalle puede ser cualquier dato
// serializable (se guarda como JSON) para poder ver el antes/después.
function registrarBitacora(int $usuarioId, string $accion, string $tabla, int $registroId, mixed $detalle = null): void {
    $stmt = db()->prepare(
        'INSERT INTO bitacora (usuario_id, accion, tabla, registro_id, detalle) VALUES (?, ?, ?, ?, ?)'
    );
    $stmt->execute([$usuarioId, $accion, $tabla, $registroId, $detalle === null ? null : json_encode($detalle, JSON_UNESCAPED_UNICODE)]);
}

// Siguiente número de documento (REQ-0001, HER-0001, S00001), atómico aunque
// dos dispositivos lo pidan al mismo tiempo. $separador va vacío para las
// cotizaciones (S00001, sin guion, como ya las conoce la app) y con guion
// para requerimientos/herramientas (REQ-0001, HER-0001).
function siguienteNumero(string $clave, string $prefijo, int $relleno = 4, string $separador = '-'): string {
    $pdo = db();
    $pdo->prepare('UPDATE correlativos SET valor = valor + 1 WHERE clave = ?')->execute([$clave]);
    $stmt = $pdo->prepare('SELECT valor FROM correlativos WHERE clave = ?');
    $stmt->execute([$clave]);
    $valor = (int) $stmt->fetchColumn();
    return $prefijo . $separador . str_pad((string) $valor, $relleno, '0', STR_PAD_LEFT);
}
