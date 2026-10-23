/** Error con el mensaje ya escrito para la persona y el código HTTP. */
export class ErrorApi extends Error {
  constructor(codigo, mensaje) {
    super(mensaje);
    this.codigo = codigo;
  }
}

export const falla = (codigo, mensaje) => new ErrorApi(codigo, mensaje);
