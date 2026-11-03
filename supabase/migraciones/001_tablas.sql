-- =============================================================================
-- 001_tablas.sql
-- Traducción del modelo entidad-relación (docs/modelo-er.png) a PostgreSQL.
-- Nombres en español, en minúsculas y sin tildes.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- ACTIVIDAD: tipo de actividad que se puede programar (yoga, crossfit…).
-- -----------------------------------------------------------------------------
create table public.actividad (
    codigo_actividad  bigint generated always as identity primary key,
    nombre            text    not null unique,
    descripcion       text,
    duracion          integer not null check (duracion > 0),        -- en minutos
    nivel             text    not null
                      check (nivel in ('principiante', 'intermedio', 'avanzado'))
);


-- -----------------------------------------------------------------------------
-- ENTRENADOR
-- usuario_id enlaza con la cuenta de Supabase Auth (para que pueda iniciar
-- sesión y proponer clases). La contraseña la guarda Supabase Auth, no nosotros.
-- -----------------------------------------------------------------------------
create table public.entrenador (
    dni_entrenador  text primary key,
    nombre          text not null,
    apellidos       text not null,
    telefono        text,
    email           text not null unique,
    especialidad    text,
    usuario_id      uuid unique references auth.users (id) on delete set null
);


-- -----------------------------------------------------------------------------
-- CLIENTE
-- En el diagrama hay "contraseña": NO se guarda aquí. Supabase Auth ya guarda
-- la contraseña cifrada en auth.users; usuario_id es el enlace con esa cuenta.
-- -----------------------------------------------------------------------------
create table public.cliente (
    dni_cliente       text primary key,
    nombre            text not null,
    apellidos         text not null,
    fecha_nacimiento  date,
    telefono          text,
    email             text not null unique,
    fecha_alta        date not null default current_date,
    usuario_id        uuid unique references auth.users (id) on delete set null
);


-- -----------------------------------------------------------------------------
-- CLASE: una sesión concreta (día y hora) de una actividad, impartida por un
-- entrenador.  actividad 1 ── N clase   y   entrenador 1 ── N clase
-- -----------------------------------------------------------------------------
create table public.clase (
    codigo_clase      bigint generated always as identity primary key,
    fecha             date not null,
    hora_inicio       time not null,
    hora_fin          time not null,
    estado            text not null default 'programada'
                      check (estado in ('programada', 'cancelada')),
    codigo_actividad  bigint not null
                      references public.actividad (codigo_actividad)
                      on delete restrict,
    dni_entrenador    text not null
                      references public.entrenador (dni_entrenador)
                      on update cascade
                      on delete restrict,
    check (hora_fin > hora_inicio)
);

create index clase_codigo_actividad_idx on public.clase (codigo_actividad);
create index clase_dni_entrenador_idx   on public.clase (dni_entrenador);
create index clase_fecha_idx            on public.clase (fecha);


-- -----------------------------------------------------------------------------
-- PAGO: mensualidad pagada por un cliente.   cliente 1 ── N pago
-- -----------------------------------------------------------------------------
create table public.pago (
    codigo_pago   bigint generated always as identity primary key,
    fecha_pago    date not null default current_date,
    mes           smallint not null check (mes between 1 and 12),
    anio          smallint not null check (anio >= 2000),
    importe       numeric(8, 2) not null check (importe > 0),
    metodo_pago   text not null
                  check (metodo_pago in ('efectivo', 'tarjeta', 'transferencia', 'bizum')),
    dni_cliente   text not null
                  references public.cliente (dni_cliente)
                  on update cascade
                  on delete restrict,
    -- Una sola mensualidad por cliente y mes.
    unique (dni_cliente, anio, mes)
);


-- -----------------------------------------------------------------------------
-- RESERVA: resuelve la relación N:M entre cliente y clase.
-- La clave primaria es la pareja (dni_cliente, codigo_clase): un cliente no
-- puede tener dos reservas para la misma clase. Si cancela y vuelve a
-- apuntarse, se cambia el estado de la misma fila.
-- -----------------------------------------------------------------------------
create table public.reserva (
    dni_cliente    text   not null
                   references public.cliente (dni_cliente)
                   on update cascade
                   on delete cascade,
    codigo_clase   bigint not null
                   references public.clase (codigo_clase)
                   on delete cascade,
    fecha_reserva  date not null default current_date,
    hora_reserva   time not null default localtime,
    estado         text not null default 'confirmada'
                   check (estado in ('confirmada', 'cancelada')),
    asistencia     boolean not null default false,
    primary key (dni_cliente, codigo_clase)
);

-- La PK ya sirve para buscar por dni_cliente; este índice sirve para buscar
-- "quién está apuntado a esta clase".
create index reserva_codigo_clase_idx on public.reserva (codigo_clase);


-- -----------------------------------------------------------------------------
-- REGLA DE NEGOCIO: máximo 8 reservas confirmadas al mes por cliente, y solo
-- en clases programadas que no hayan pasado.
-- Se comprueba con un trigger cada vez que se crea una reserva confirmada o
-- una reserva cancelada vuelve a pasar a confirmada.
-- -----------------------------------------------------------------------------
create function public.comprobar_reserva()
returns trigger
language plpgsql
security definer          -- necesita ver todas las reservas del cliente
set search_path = ''
as $$
declare
    v_clase      public.clase%rowtype;
    v_ocupadas   integer;
begin
    -- Solo nos interesa cuando la reserva queda "confirmada".
    if new.estado <> 'confirmada' then
        return new;
    end if;
    if tg_op = 'UPDATE' and old.estado = 'confirmada' then
        return new;  -- ya estaba confirmada: no cambia el recuento
    end if;

    select * into v_clase from public.clase where codigo_clase = new.codigo_clase;

    if v_clase.estado <> 'programada' then
        raise exception 'La clase % está cancelada', new.codigo_clase;
    end if;
    if v_clase.fecha < current_date then
        raise exception 'La clase % ya ha pasado', new.codigo_clase;
    end if;

    -- Bloquea al cliente para que dos reservas simultáneas no se salten el límite.
    perform 1 from public.cliente where dni_cliente = new.dni_cliente for update;

    select count(*) into v_ocupadas
    from public.reserva r
    join public.clase c on c.codigo_clase = r.codigo_clase
    where r.dni_cliente = new.dni_cliente
      and r.estado = 'confirmada'
      and r.codigo_clase <> new.codigo_clase
      and date_trunc('month', c.fecha) = date_trunc('month', v_clase.fecha);

    if v_ocupadas >= 8 then
        raise exception 'Límite alcanzado: ya tienes 8 clases reservadas ese mes';
    end if;

    return new;
end;
$$;

create trigger reserva_comprobar
before insert or update of estado on public.reserva
for each row execute function public.comprobar_reserva();

-- Nadie debe poder llamar a esta función directamente desde la API.
revoke execute on function public.comprobar_reserva() from public, anon, authenticated;
