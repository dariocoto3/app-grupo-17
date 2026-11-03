# CLAUDE.md — App del grupo 17

## Qué es la app

Aplicación web para un **centro de entrenamiento**:

- Los **clientes** pagan una **mensualidad** que les da derecho a asistir a
  **un máximo de 8 clases al mes**.
- Los **entrenadores** proponen **clases** (con fecha y hora) de distintas
  **actividades** (por ejemplo: yoga, crossfit, spinning…).
- Los clientes se **apuntan (reservan)** a las clases que quieran, dentro de
  su límite mensual, y pueden cancelar la reserva.

## Miembros del grupo 17

- Darío
- Nico
- Gonzalo

## Tecnología

- **Página estática**: HTML + CSS + JavaScript "a pelo", **sin compilación**
  (nada de npm, bundlers, React, etc.). Lo que hay en el repositorio es
  exactamente lo que se publica.
- **Supabase** como base de datos (PostgreSQL) y autenticación.
  La librería `supabase-js` se carga **desde un CDN** con una etiqueta
  `<script>`, no se instala.
- **Cloudflare Pages** para publicar la web.
- Las migraciones SQL están en `supabase/migraciones/`, numeradas en orden
  (`001_...sql`, `002_...sql`, …).

## Modelo de datos (resumen)

El diagrama original está en `docs/modelo-er.png`. Nombres de tablas y columnas
en español, en minúsculas y sin tildes.

| Tabla        | Clave primaria                  | Claves foráneas                                   |
|--------------|---------------------------------|---------------------------------------------------|
| `actividad`  | `codigo_actividad`              | —                                                 |
| `entrenador` | `dni_entrenador`                | `usuario_id` → `auth.users`                       |
| `cliente`    | `dni_cliente`                   | `usuario_id` → `auth.users`                       |
| `clase`      | `codigo_clase`                  | `codigo_actividad` → actividad, `dni_entrenador` → entrenador |
| `pago`       | `codigo_pago`                   | `dni_cliente` → cliente                           |
| `reserva`    | (`dni_cliente`, `codigo_clase`) | `dni_cliente` → cliente, `codigo_clase` → clase   |

Relaciones:

- Una **actividad** se programa en muchas **clases** (1:N).
- Un **entrenador** imparte muchas **clases** (1:N).
- Un **cliente** realiza muchos **pagos** (1:N).
- **Clientes** y **clases** son N:M, resuelto con la tabla **reserva**.

Reglas de negocio implementadas en la base de datos:

- Un cliente no puede tener más de **8 reservas confirmadas** en clases del
  mismo mes.
- Solo se puede reservar una clase `programada` y que no haya pasado.

Las contraseñas **no** se guardan en nuestras tablas: las gestiona Supabase Auth
(`auth.users`), y `cliente.usuario_id` / `entrenador.usuario_id` enlazan con ella.

## Reglas para trabajar en este repositorio

1. **Explicar cada cambio pensando en principiantes.** Somos estudiantes:
   cada cambio debe ir acompañado de una explicación sencilla de qué se ha
   hecho y por qué, sin dar por sabido el vocabulario técnico.
2. **No cambiar tablas sin aprobación.** Cualquier cambio en la estructura de
   la base de datos (crear, borrar o modificar tablas, columnas, claves,
   políticas…) hay que proponerlo primero y esperar a que el grupo lo apruebe.
   Tampoco se aplica nada en Supabase sin nuestra aprobación explícita.
   Los cambios se hacen siempre con una **nueva** migración numerada; no se
   editan migraciones que ya se hayan aplicado.
3. **No usar nunca la secret key de Supabase** (ni la antigua `service_role`).
   En el código de la web solo se usa la **publishable key** (antigua `anon`),
   que es pública por diseño; la seguridad la dan las políticas RLS.
   Nunca se escribe ninguna clave secreta en el repositorio.
