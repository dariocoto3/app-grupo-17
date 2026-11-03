-- =============================================================================
-- 002_seguridad.sql
-- Row Level Security (RLS) y políticas iniciales.
--
-- Idea general: con RLS activado, una tabla NO deja leer ni escribir NADA
-- salvo lo que permita expresamente alguna política.
--   * anon          = visitante sin iniciar sesión
--   * authenticated = usuario que ha iniciado sesión (cliente o entrenador)
-- Lo que no se permite aquí (dar de alta entrenadores, registrar pagos…) se
-- hace desde el panel de Supabase por el administrador.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Activar RLS en todas las tablas
-- -----------------------------------------------------------------------------
alter table public.actividad  enable row level security;
alter table public.entrenador enable row level security;
alter table public.cliente    enable row level security;
alter table public.clase      enable row level security;
alter table public.pago       enable row level security;
alter table public.reserva    enable row level security;


-- -----------------------------------------------------------------------------
-- 2. Funciones de ayuda: ¿quién es el usuario que ha iniciado sesión?
--    Son "security definer" para poder consultar las tablas sin que las propias
--    políticas se llamen a sí mismas en bucle.
-- -----------------------------------------------------------------------------

-- DNI del cliente que ha iniciado sesión (o null si no es cliente).
create function public.mi_dni_cliente()
returns text
language sql stable security definer set search_path = ''
as $$
    select dni_cliente from public.cliente where usuario_id = (select auth.uid());
$$;

-- DNI del entrenador que ha iniciado sesión (o null si no es entrenador).
create function public.mi_dni_entrenador()
returns text
language sql stable security definer set search_path = ''
as $$
    select dni_entrenador from public.entrenador where usuario_id = (select auth.uid());
$$;

-- ¿El cliente indicado está apuntado a alguna clase del entrenador conectado?
create function public.es_alumno_mio(p_dni_cliente text)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1
        from public.reserva r
        join public.clase c on c.codigo_clase = r.codigo_clase
        where r.dni_cliente = p_dni_cliente
          and c.dni_entrenador = public.mi_dni_entrenador()
    );
$$;

-- ¿La clase indicada la imparte el entrenador conectado?
create function public.es_clase_mia(p_codigo_clase bigint)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.clase
        where codigo_clase = p_codigo_clase
          and dni_entrenador = public.mi_dni_entrenador()
    );
$$;

-- Los visitantes anónimos no necesitan estas funciones.
revoke execute on function public.mi_dni_cliente()          from public, anon;
revoke execute on function public.mi_dni_entrenador()       from public, anon;
revoke execute on function public.es_alumno_mio(text)       from public, anon;
revoke execute on function public.es_clase_mia(bigint)      from public, anon;
grant  execute on function public.mi_dni_cliente()          to authenticated;
grant  execute on function public.mi_dni_entrenador()       to authenticated;
grant  execute on function public.es_alumno_mio(text)       to authenticated;
grant  execute on function public.es_clase_mia(bigint)      to authenticated;


-- -----------------------------------------------------------------------------
-- 3. ACTIVIDAD: catálogo público; solo los entrenadores lo gestionan.
-- -----------------------------------------------------------------------------
create policy "actividad: cualquiera puede verlas"
on public.actividad for select
to anon, authenticated
using (true);

create policy "actividad: entrenadores pueden crear"
on public.actividad for insert
to authenticated
with check ((select public.mi_dni_entrenador()) is not null);

create policy "actividad: entrenadores pueden modificar"
on public.actividad for update
to authenticated
using      ((select public.mi_dni_entrenador()) is not null)
with check ((select public.mi_dni_entrenador()) is not null);

-- (Sin política de DELETE: borrar actividades solo desde el panel.)


-- -----------------------------------------------------------------------------
-- 4. ENTRENADOR: los usuarios con sesión pueden ver a los entrenadores
--    (para saber quién da cada clase). Cada entrenador edita su propia ficha.
--    Altas y bajas: desde el panel.
-- -----------------------------------------------------------------------------
create policy "entrenador: usuarios con sesión pueden verlos"
on public.entrenador for select
to authenticated
using (true);

create policy "entrenador: cada uno modifica su ficha"
on public.entrenador for update
to authenticated
using      (usuario_id = (select auth.uid()))
with check (usuario_id = (select auth.uid()));


-- -----------------------------------------------------------------------------
-- 5. CLIENTE: cada cliente ve y edita solo su ficha y puede crearla al
--    registrarse. El entrenador ve los datos de quien va a sus clases.
-- -----------------------------------------------------------------------------
create policy "cliente: ver mi ficha"
on public.cliente for select
to authenticated
using (usuario_id = (select auth.uid()));

create policy "cliente: entrenador ve a sus alumnos"
on public.cliente for select
to authenticated
using (public.es_alumno_mio(dni_cliente));

create policy "cliente: crear mi ficha al registrarme"
on public.cliente for insert
to authenticated
with check (usuario_id = (select auth.uid()));

create policy "cliente: modificar mi ficha"
on public.cliente for update
to authenticated
using      (usuario_id = (select auth.uid()))
with check (usuario_id = (select auth.uid()));

-- (Sin DELETE: las bajas, desde el panel.)


-- -----------------------------------------------------------------------------
-- 6. CLASE: cualquier usuario con sesión ve el horario. Cada entrenador
--    crea, modifica y borra solo SUS clases.
-- -----------------------------------------------------------------------------
create policy "clase: usuarios con sesión pueden verlas"
on public.clase for select
to authenticated
using (true);

create policy "clase: entrenador crea sus clases"
on public.clase for insert
to authenticated
with check (dni_entrenador = (select public.mi_dni_entrenador()));

create policy "clase: entrenador modifica sus clases"
on public.clase for update
to authenticated
using      (dni_entrenador = (select public.mi_dni_entrenador()))
with check (dni_entrenador = (select public.mi_dni_entrenador()));

create policy "clase: entrenador borra sus clases"
on public.clase for delete
to authenticated
using (dni_entrenador = (select public.mi_dni_entrenador()));


-- -----------------------------------------------------------------------------
-- 7. PAGO: cada cliente ve solo sus pagos. Nadie los crea ni toca desde la
--    web (los registra el administrador desde el panel).
-- -----------------------------------------------------------------------------
create policy "pago: ver mis pagos"
on public.pago for select
to authenticated
using (dni_cliente = (select public.mi_dni_cliente()));


-- -----------------------------------------------------------------------------
-- 8. RESERVA
--    Cliente: ve, crea y cancela SUS reservas (no las borra).
--    Entrenador: ve las reservas de SUS clases y marca la asistencia.
-- -----------------------------------------------------------------------------
create policy "reserva: cliente ve las suyas"
on public.reserva for select
to authenticated
using (dni_cliente = (select public.mi_dni_cliente()));

create policy "reserva: entrenador ve las de sus clases"
on public.reserva for select
to authenticated
using (public.es_clase_mia(codigo_clase));

create policy "reserva: cliente se apunta"
on public.reserva for insert
to authenticated
with check (
    dni_cliente = (select public.mi_dni_cliente())
    and estado = 'confirmada'
    and asistencia = false
);

create policy "reserva: cliente modifica las suyas"
on public.reserva for update
to authenticated
using      (dni_cliente = (select public.mi_dni_cliente()))
with check (dni_cliente = (select public.mi_dni_cliente()));

create policy "reserva: entrenador modifica las de sus clases"
on public.reserva for update
to authenticated
using      (public.es_clase_mia(codigo_clase))
with check (public.es_clase_mia(codigo_clase));


-- -----------------------------------------------------------------------------
-- 9. Las políticas dicen QUÉ FILAS se pueden tocar, no QUÉ COLUMNAS.
--    Este trigger completa la seguridad de "reserva":
--      * nadie cambia el cliente ni la clase de una reserva existente;
--      * el cliente solo puede cambiar el estado (cancelar / reactivar);
--      * el entrenador solo puede cambiar la asistencia.
--    (Desde el panel de Supabase, sin usuario conectado, no se aplica.)
-- -----------------------------------------------------------------------------
create function public.proteger_reserva()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if (select auth.uid()) is null then
        return new;  -- administrador desde el panel
    end if;

    if new.dni_cliente <> old.dni_cliente or new.codigo_clase <> old.codigo_clase
       or new.fecha_reserva <> old.fecha_reserva or new.hora_reserva <> old.hora_reserva then
        raise exception 'No se puede cambiar el cliente, la clase ni la fecha de una reserva';
    end if;

    if new.asistencia <> old.asistencia
       and not public.es_clase_mia(new.codigo_clase) then
        raise exception 'Solo el entrenador de la clase puede marcar la asistencia';
    end if;

    if new.estado <> old.estado
       and new.dni_cliente is distinct from public.mi_dni_cliente() then
        raise exception 'Solo el propio cliente puede cancelar o reactivar su reserva';
    end if;

    return new;
end;
$$;

create trigger reserva_proteger
before update on public.reserva
for each row execute function public.proteger_reserva();

revoke execute on function public.proteger_reserva() from public, anon, authenticated;
