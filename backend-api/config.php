<?php
// Configuración del backend del Cotizador ICR — PHP + PostgreSQL, en Docker
// detrás de Traefik en el mismo VPS del resto del ecosistema ICR (mismo
// patrón que icr-almacen-mvp: un contenedor Postgres propio + un contenedor
// de la API). Todo se lee del entorno (ver docker-compose.yml / .env), nunca
// hardcodeado — así el mismo config.php sirve en cualquier contenedor sin
// tocar código.

// define() (no const): son valores de entorno, recién conocidos en tiempo
// de ejecución dentro del contenedor — una const de PHP exige una expresión
// constante en tiempo de compilación y no acepta leer getenv() ahí.
define('PGHOST', getenv('PGHOST') ?: 'db');
define('PGPORT', getenv('PGPORT') ?: '5432');
define('PGDATABASE', getenv('PGDATABASE') ?: 'icr_cotizador');
define('PGUSER', getenv('PGUSER') ?: 'icr_cotizador');
define('PGPASSWORD', getenv('PGPASSWORD') ?: 'changeme');

// URL base de la API del ERP (sin / al final) — acá se valida el login,
// nunca contra una tabla de usuarios propia. El ERP corre en su propio
// contenedor en el mismo VPS, pero se llama por su dominio público (HTTPS,
// a través de Traefik): es una llamada servidor-a-servidor, no desde un
// navegador, así que no hace falta unir redes Docker ni tocar CORS.
define('ERP_API_URL', getenv('ERP_API_URL') ?: 'https://erp.inversionesicr.com/api');

// Zona horaria usada tanto en PHP (date(), date_default_timezone_set) como
// en la sesión de Postgres (ver db(), más abajo) — así NOW() en SQL y
// date('Y-m-d H:i:s') en PHP coinciden.
date_default_timezone_set('America/Lima');

function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = 'pgsql:host=' . PGHOST . ';port=' . PGPORT . ';dbname=' . PGDATABASE;
        $pdo = new PDO($dsn, PGUSER, PGPASSWORD, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        $pdo->exec("SET TIME ZONE 'America/Lima'");
    }
    return $pdo;
}

// Respuesta JSON estándar de toda la API — mismo sobre {status,data,error}
// que ya usa el ERP, para que el cliente Flutter maneje todo igual.
function responder(array $data, int $http = 200): void {
    http_response_code($http);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['status' => 'ok', 'data' => $data, 'error' => null], JSON_UNESCAPED_UNICODE);
    exit;
}

function responderError(string $codigo, string $mensaje, int $http = 400): void {
    http_response_code($http);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['status' => 'error', 'data' => null, 'error' => ['code' => $codigo, 'message' => $mensaje]], JSON_UNESCAPED_UNICODE);
    exit;
}

function cuerpoJson(): array {
    $raw = file_get_contents('php://input');
    $json = json_decode($raw, true);
    return is_array($json) ? $json : [];
}
