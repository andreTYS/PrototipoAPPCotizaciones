// DateFormat('d MMM', 'es') depende de datos de locale que la app no
// inicializa (para no encarecer el arranque solo por esto); además, el
// mes abreviado que trae esa tabla para setiembre es "sept", no "sep"
// como se usa en el diseño — con esta lista chica alcanza y queda exacto.
const _mesesCorto = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "29 sep" — la fecha corta de las tarjetas de las listas.
String fechaCorta(DateTime fecha) => '${fecha.day} ${_mesesCorto[fecha.month - 1]}';

/// "29 sep · 10:15"
String fechaCortaConHora(DateTime fecha) =>
    '${fechaCorta(fecha)} · ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

/// "1 ítem" / "3 ítems" (o la palabra que se pase).
String cantidadConPalabra(int n, String singular, String plural) => n == 1 ? '1 $singular' : '$n $plural';
