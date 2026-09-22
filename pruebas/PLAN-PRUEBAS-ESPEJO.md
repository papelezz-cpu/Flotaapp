# Ejercitar el espejo de `vigencias` en el preview de `dev`

Guion para la fase de doble escritura de H-04. **Se hace a mano en el preview**,
porque `portgo-pruebas` no tiene tráfico propio: esperar ahí no da señal, da
silencio.

Cada paso dice **qué hacer**, **qué campo** y **qué debe pasar en el espejo**.
Tras cada bloque se corre la sonda; si sale en rojo, se para y se mira.

```bash
node pruebas/14-sonda-espejo-vigencias.mjs
```

> **Antes de empezar**, el espejo tolerante tiene que estar aplicado:
> ```bash
> bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260922130000_vigencias_espejo_tolerante.sql
> ```
> Sin él, un fallo del espejo te impediría guardar — y el propósito de esta
> tanda es justo provocar caminos que nadie ha probado.

**URL:** el preview de `dev`. Ctrl+Shift+R primero, y comprueba que estás en
pruebas (`sb.supabaseUrl` debe decir `xskgnudiznryhgagxadu`).

---

## 1 · Alta de camión con papeles  ·  *como empresa*

**Mis unidades → dar de alta un camión.** Llena, además de lo obligatorio:

| Campo en pantalla | Va a |
|---|---|
| Tarjeta de circulación (archivo) + su vencimiento | `tarjeta_circulacion` |
| Seguro (archivo) + vencimiento | `seguro_unidad` |
| Permiso SCT (archivo) + vencimiento | `permiso_sct_unidad` |
| Verificación — vencimiento | `verificacion` |
| Materiales peligrosos (archivo) + vencimiento | `permiso_peligrosa` |
| CAAT (archivo) | `caat` |

**Debe pasar:** la sonda sube de 63 a **63 + tantos documentos como hayas
llenado**, y ninguno «falta» ni «difiere».

> Llena **al menos el CAAT**. Es el único cuyo archivo vive en `doc_caat`
> mientras existe una columna gemela `imagen_caat` que nadie usa; si el alta
> escribiera en la otra, el espejo se quedaría sin él y la sonda lo diría.

---

## 2 · Editar ese camión  ·  *como empresa*

**Mis unidades → editar el camión recién creado.** Cambia **una sola fecha**,
por ejemplo la del seguro.

**Debe pasar:** el total de la sonda **no cambia** —no se duplica nada— y la
fila del seguro lleva la fecha nueva.

Este paso es el que prueba que el guard corregido deja a la empresa mantener
sus propios papeles. Antes de la Etapa 3b esto fallaba con
`VIGENCIA_ACREDITADA`.

---

## 3 · Quitar un documento  ·  *como empresa*

En ese mismo camión, **borra la fecha de verificación** y deja el campo vacío.

**Debe pasar:** la sonda **baja en uno** y sigue sin «filas de más». Si el
total no baja, el espejo está dejando un documento fantasma: una fila que dice
vigilar un papel que ya no está.

---

## 4 · Alta de operador con exámenes  ·  *como empresa*

**Operadores → dar de alta.** Llena la licencia con su vencimiento y, sobre
todo, las **tres fechas de examen**:

| Campo | Va a | Ojo |
|---|---|---|
| Vencimiento de licencia | `licencia` | es una caducidad |
| Examen médico | `examen_medico` | es la fecha **del examen** |
| Examen toxicológico | `examen_toxicologico` | ídem |
| Carta de antecedentes | `carta_antecedentes` | ídem |

**Debe pasar:** la sonda sube y no marca diferencias. Y lo que de verdad se
comprueba aquí: que el espejo guarda **la fecha que escribiste**, no una
calculada. La caducidad se deriva después con `vigencia_vence_el()`, que le
suma 12 meses según el catálogo.

Para verlo con tus ojos, tras el alta:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('sa',A); await s.login(c.superadmin.email,c.superadmin.password);
  const {data}=await s.select('vigencias','select=entidad_id,tipo_documento,fecha_documento&tipo_documento=like.examen*');
  console.table(data);});"
```

La fecha que salga tiene que ser **la que tecleaste**, no un año más.

---

## 5 · La empresa propone sus documentos  ·  *como empresa*

**Mis unidades → Perfil de empresa.** Sube permiso SCT, seguro RC y seguro de
carga con sus vencimientos, y guarda.

**Debe pasar:** aparecen filas nuevas **en estado `pendiente`**, no `vigente`.
La empresa propone; no se acredita sola.

Para confirmarlo:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('sa',A); await s.login(c.superadmin.email,c.superadmin.password);
  const {data}=await s.select('vigencias','select=entidad_tipo,tipo_documento,estado,fecha_documento&entidad_tipo=eq.perfil');
  console.table(data);});"
```

---

## 6 · El superadmin acredita  ·  *como superadmin*  ·  **el paso clave**

**Por aprobar → documentos de la empresa → aprobar.**

Ese botón hace **una sola escritura** que copia las columnas `_pendiente` a las
reales y deja las pendientes en nulo. Así que dispara el espejo en las dos
direcciones a la vez.

**Debe pasar:**
- las filas `pendiente` de ese perfil **desaparecen**,
- aparecen —o se actualizan— las mismas en `vigente`,
- el total de la sonda queda igual que antes de aprobar,
- y ninguna «de más».

Si quedan filas `pendiente` huérfanas, el espejo no está reflejando el
vaciado. Es el caso que más probabilidad tenía de fallar, porque es el único
donde una misma escritura crea una fila y borra otra.

---

## 7 · Y el que no debe poder hacerse

Como **empresa**, intenta cambiar tú mismo el estado de uno de tus documentos
a `vigente` por el API:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('emp',A); await s.login(c.empresa.email,c.empresa.password);
  const {data}=await s.select('vigencias','select=id,tipo_documento,estado&estado=eq.pendiente&limit=1');
  if(!data?.length){console.log('  no hay ninguna pendiente que probar');return;}
  const r=await s.update('vigencias','id=eq.'+data[0].id,{estado:'vigente'});
  console.log(r.ok? '  ✗ FALLA: se acredito sola' : '  ✓ rechazado: HTTP '+r.status+' '+(r.data?.message||''));});"
```

Tiene que salir **rechazado**. Si sale «se acreditó sola», H-02 está reabierto
por la puerta de atrás y hay que parar todo.

---

## Al terminar

```bash
node pruebas/14-sonda-espejo-vigencias.mjs
```

Verde en los tres bloques —ninguna falta, ninguna difiere, ninguna de más—
significa que el espejo aguantó los caminos reales, no solo los del banco.
**Ahí, y no antes, la Etapa 4 tiene una base comprobada sobre la que mover las
lecturas.**

Si algo sale rojo, la sonda nombra entidad, documento y los dos valores. Eso
basta para saber qué flujo lo dejó así.
