# Ejercitar el espejo de `vigencias` en el preview de `dev`

Guion paso a paso para la fase de doble escritura de H-04, **con valores
concretos**. Se hace a mano en el preview, porque `portgo-pruebas` no tiene
tráfico propio: esperar ahí no da señal, da silencio.

## Cómo leer este guion

Hay dos sitios donde se escribe, y conviene no confundirlos:

| El bloque dice | Va en |
|---|---|
| ```bash``` | **la terminal** (Git Bash), dentro de `~/Documents/Flotaapp` |
| ```js``` | **la consola del navegador**: F12 → pestaña Console |
| sin etiqueta | **no se ejecuta**: es una URL o un ejemplo de lo que vas a ver |

Lo que se hace **en la aplicación** —rellenar formularios, pulsar botones— va
descrito en texto, no en bloques de código.

## Por qué cada fecha es distinta

Todas las fechas sugeridas son **únicas**. Si el espejo mapeara un documento
al tipo equivocado, la fecha «rara» aparecería colgada del documento que no
es, y se vería de un vistazo. Con fechas repetidas, un error de mapeo pasa
desapercibido.

## Antes de empezar

```bash
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260922130000_vigencias_espejo_tolerante.sql
```

Sin el espejo tolerante, un fallo suyo te impediría guardar — y el propósito
de esta tanda es justo provocar caminos que nadie ha probado.

### a) En el navegador — abre el preview y confirma que NO es producción

Entra a:

```
https://portgo-git-dev-salvador-s-projects13.vercel.app/app.html
```

Pulsa **Ctrl+Shift+R** (recarga forzada, para no quedarte con una versión
vieja en cache).

Ahora abre la consola del navegador: **tecla F12** → pestaña **Console**.
Pega esto y pulsa Enter:

```js
sb.supabaseUrl
```

**Tiene que responder `"https://xskgnudiznryhgagxadu.supabase.co"`.**

Si responde `xnyqsewaluezkkrlyhxg`, **estás en producción y no debes seguir**:
las dos aplicaciones se ven idénticas y tienen los mismos datos, así que la
pantalla no te lo va a decir. Esta línea es la única forma de saberlo.

> Si Firefox contesta *«Scripts may not be pasted…»*, escribe `allow pasting`
> y Enter. Solo la primera vez.

### b) En la terminal — apunta el número de partida

Esto **no** va en el navegador. Va en tu terminal (Git Bash), dentro de la
carpeta del proyecto:

```bash
cd ~/Documents/Flotaapp
node pruebas/14-sonda-espejo-vigencias.mjs
```

Vas a ver algo así:

```
── Sonda del espejo de vigencias (H-04 etapa 3) ──
   proyecto: https://xskgnudiznryhgagxadu.supabase.co
   paridad:  paridad DIVERGE (66 diferencias, ...)

   pares con dato en el origen: 63   ·   filas en vigencias: 63
                                ▲▲
                     este número es el que hay que apuntar

     OK    Ninguna fila del origen falta en el espejo
     OK    Ninguna fila difiere en archivo o fecha
     OK    El espejo no tiene filas de más
```

**Apunta ese número: hoy son 63.** Es contra el que vas a comparar después de
cada paso.

Dos cosas de esa salida que conviene entender antes de asustarse:

- **Los dos números tienen que ser iguales.** «Pares con dato en el origen» es
  lo que hay en las columnas viejas; «filas en vigencias» es lo que hay en la
  tabla nueva. Que coincidan es justamente lo que se está comprobando.
- **`paridad DIVERGE` es lo esperado, no un problema.** Pruebas se separa de
  producción precisamente porque tiene las migraciones de H-04, que producción
  no tiene. Lo que importa aquí son las tres líneas de `OK`.

---

## 1 · Alta de camión  ·  *como empresa*

**Mis unidades → dar de alta un camión.** Pon placas reconocibles, por ejemplo
**`ESP-001`**, y llena lo obligatorio (tipo, capacidad).

Estas son las fechas, con el nombre **exacto** de la etiqueta en pantalla:

| Etiqueta en pantalla | Escribe | Tipo de documento |
|---|---|---|
| Fecha de vencimiento TC | `2027-01-11` | `tarjeta_circulacion` |
| Vencimiento del seguro | `2027-02-12` | `seguro_unidad` |
| Vencimiento del permiso SCT | `2027-03-13` | `permiso_sct_unidad` |
| Vigencia CAAT | `2027-04-14` | `caat` |
| Vencimiento verificación vehicular | `2027-05-15` | `verificacion` |

Adjunta archivo donde el alta lo pide: **tarjeta de circulación, seguro y
permiso SCT**. Cualquier PDF o imagen vale.

> **El alta NO pide archivo para el CAAT ni para la verificación** — solo sus
> fechas. Sus archivos se suben desde el formulario de edición, y eso se
> prueba en el paso 2. Comprobado en `js/admin.js`, no supuesto.

**Debe pasar:** la sonda sube de 63 a **68** (cinco documentos nuevos), sin
«falta» ni «difiere».

```bash
node pruebas/14-sonda-espejo-vigencias.mjs
```

---

## 2 · Editar ese camión  ·  *como empresa*

**Mis unidades → editar el camión `ESP-001`.**

Cambia la **Vigencia CAAT** de `2027-04-14` a **`2028-04-14`** y **adjunta un
archivo** en «Adjuntar CAAT renovado».

> El archivo no es opcional: hay un candado que dice *«Para renovar la vigencia
> de CAAT debes adjuntar el documento renovado»*. Solo se salta si eres
> superadmin. Y de paso es la única forma de escribir `doc_caat`, que es lo que
> queremos ver llegar al espejo.

**Debe pasar:**
- el total **sigue en 68** — se actualiza, no se duplica,
- la fila del CAAT lleva `2028-04-14` **y** un `archivo_path`.

Compruébalo con detalle. **No uses `console.table` para contar**: numera desde
cero, así que con 53 filas el último índice que imprime es `52` y parece que
falta una. Este comando imprime el total aparte:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('sa',A); await s.login(c.superadmin.email,c.superadmin.password);
  const {data}=await s.select('vigencias','select=entidad_id,tipo_documento,fecha_documento,archivo_path&entidad_tipo=eq.camion&order=entidad_id,tipo_documento');
  console.log('  filas de camion: '+data.length);
  data.forEach(x=>console.log('   ',x.entidad_id.padEnd(12),x.tipo_documento.padEnd(22),String(x.fecha_documento).padEnd(12),x.archivo_path?'con archivo':'(sin archivo)'));});"
```

Este paso es además el que prueba que **el guard corregido deja a la empresa
mantener sus propios papeles**. Antes de la Etapa 3 esto fallaba con
`VIGENCIA_ACREDITADA`.

---

## 3 · Borrar una unidad  ·  *como empresa*

> **Este paso cambió el 2026-09-22.** Decía «entra como superadmin y vacía la
> fecha de verificación vehicular», y **no se puede hacer**. Dos razones, las
> dos comprobadas en el código:
>
> - El superadmin **no tiene acceso a «Mis unidades»** — su lista de accesos
>   ([js/views.js:93-104](../js/views.js)) no incluye esa pantalla ni
>   «Operadores», y `editarCamion()` solo se llama desde la tarjeta de esa
>   lista ([js/admin.js:147](../js/admin.js)). No hay ruta.
> - La empresa sí llega al formulario, pero **no puede vaciar una fecha**: el
>   candado de [js/admin.js:534](../js/admin.js) exige adjuntar documento en
>   cuanto la fecha cambia, y borrarla cuenta como cambio.
>
> Resultado: **ningún rol puede vaciar la fecha de un documento de camión
> desde la interfaz.** Lo que sí vacía filas del espejo es el paso 6 (cuando
> el superadmin acredita, las columnas `_pendiente` se limpian) — así que ese
> camino no se queda sin probar, solo se prueba más adelante.

En su lugar este paso prueba **el borrado de la unidad entera**, que es lo que
el espejo aprendió a seguir en la Etapa 3c y antes no seguía.

**Antes de empezar, aplica la etapa 3c a pruebas** (solo una vez):

```bash
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260922140000_vigencias_espejo_borrado.sql
```

Debe imprimir `fantasmas barridos: 0` y `los 5 triggers escuchan INSERT,
UPDATE y DELETE`.

### a) En la aplicación

**Mis unidades → dar de alta**, una unidad desechable:

| Campo | Valor |
|---|---|
| ID / número económico | `ESP-BORRAR` |
| Tipo | el mismo que usaste en `ESP-001` |
| Vencimiento verificación vehicular | `2029-01-09` |

Guárdala. Luego, en su tarjeta, pulsa **🗑** y confirma.

### b) En la terminal

```bash
node pruebas/14-sonda-espejo-vigencias.mjs
```

**Debe pasar:**
- al dar de alta, el total sube a **69** y aparece una fila
  `camion|ESP-BORRAR|verificacion`,
- al borrarla, el total vuelve a **68** y esa fila **desaparece**,
- y sobre todo: **«El espejo no tiene filas de más» sigue en OK**. Si la fila
  sobrevive al borrado, la sonda la cantará ahí — es un documento que dice
  vigilar un camión que ya no existe.

Sin la Etapa 3c aplicada este paso falla, y ese es justo el punto: el hueco
era real. Comprobado en banco local con
[pruebas/banco-local/h04-etapa3c.sql](banco-local/h04-etapa3c.sql), bloque 3.

---

## 4 · Alta de operador  ·  *como empresa*

**Operadores → dar de alta.** Nombre reconocible, por ejemplo **`Espejo Uno`**.

| Etiqueta en pantalla | Escribe | Tipo |
|---|---|---|
| Vencimiento de la licencia | `2028-06-16` | `licencia` |
| Examen médico | `2026-07-17` | `examen_medico` |
| Examen toxicológico | `2026-08-18` | `examen_toxicologico` |
| Carta de antecedentes | `2026-09-19` | `carta_antecedentes` |

Adjunta los documentos que pida. La **fecha de expedición** de la licencia
llénala si quieres — **no entra en el espejo a propósito**, por tu decisión del
19 de septiembre: solo interesa cuándo vence.

**Debe pasar:** la sonda sube a **72** (cuatro documentos) sin diferencias.

Y lo que de verdad se comprueba aquí — que el espejo guarda **la fecha que
tecleaste**, no una calculada:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('sa',A); await s.login(c.superadmin.email,c.superadmin.password);
  const {data}=await s.select('vigencias','select=tipo_documento,fecha_documento&entidad_tipo=eq.operador&order=tipo_documento');
  for (const v of data) {
    const {data:d}=await s.rpc('vigencia_vence_el',{p_tipo:v.tipo_documento,p_fecha:v.fecha_documento});
    console.log(v.tipo_documento.padEnd(22), 'capturada', v.fecha_documento, '-> vence', d);
  }});"
```

El examen médico debe decir **capturada `2026-07-17` → vence `2027-07-17`**:
guardada tal cual, caducidad derivada. Si guardara `2027-07-17`, alguien habría
horneado la regla en los datos.

---

## 5 · La empresa propone sus documentos  ·  *como empresa*

**Mis unidades → Perfil de empresa.** Sube los tres documentos con sus fechas:

| Documento | Escribe |
|---|---|
| Permiso SCT | `2027-10-20` |
| Seguro RC | `2027-11-21` |
| Seguro de carga | `2027-12-22` |

**Debe pasar:** aparecen tres filas **en estado `pendiente`**, no `vigente`. La
empresa propone; no se acredita sola. Total: **75**.

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('sa',A); await s.login(c.superadmin.email,c.superadmin.password);
  const {data}=await s.select('vigencias','select=tipo_documento,estado,fecha_documento&entidad_tipo=eq.perfil&order=tipo_documento,estado');
  console.log('  filas de perfil: '+data.length);
  data.forEach(x=>console.log('   ',x.tipo_documento.padEnd(16),x.estado.padEnd(10),x.fecha_documento));});"
```

---

## 6 · El superadmin acredita  ·  **el paso clave**

Entra **como superadmin** → **Por aprobar** → los documentos de esa empresa →
**aprobar**.

Ese botón hace **una sola escritura** que copia las columnas `_pendiente` a las
reales y deja las pendientes en nulo. Dispara el espejo en las dos direcciones
a la vez: borra tres filas y crea tres.

**Debe pasar:**
- las tres `pendiente` **desaparecen**,
- aparecen las tres en `vigente`, con **las mismas fechas**: `2027-10-20`,
  `2027-11-21`, `2027-12-22`,
- el total **sigue en 75**,
- ninguna «de más».

Repite la consulta del paso 5: debes ver tres filas, todas `vigente`.

**Es el paso con más probabilidad de fallar**, porque es el único donde una
misma escritura borra una fila y crea otra.

---

## 7 · Y lo que no debe poder hacerse

Como **empresa**, intenta acreditarte un documento por el API:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('emp',A); await s.login(c.empresa.email,c.empresa.password);
  const {data}=await s.select('vigencias','select=id,tipo_documento,estado&entidad_tipo=eq.perfil&estado=eq.vigente&limit=1');
  if(!data?.length){console.log('  no hay ninguna vigente de perfil que probar');return;}
  const r=await s.update('vigencias','id=eq.'+data[0].id,{fecha_documento:'2099-01-01'});
  // r.ok solo dice que hubo HTTP 200 — con RLS eso pasa aun con 0 filas
  // afectadas (ver CLAUDE.md, actualizarConfirmado). Hay que mirar r.data.
  const cambio = r.ok && Array.isArray(r.data) && r.data.length > 0;
  console.log(cambio ? '  FALLA: la empresa movio la fecha de su documento acreditado — H-02 REABIERTO'
                  : '  OK: rechazado (0 filas afectadas), HTTP '+r.status+' '+(r.data?.message||''));});"
```

Tiene que salir **rechazado**. Si sale `FALLA`, paramos todo: H-02 estaría
reabierto por la puerta de atrás.

---

## Al terminar

```bash
node pruebas/14-sonda-espejo-vigencias.mjs
```

**Esperado: 75 pares, 75 filas**, ninguna falta, ninguna difiere, ninguna de
más.

| Paso | Total tras el paso |
|---|---|
| Partida | 63 |
| 1 · alta de camión | 68 |
| 2 · editar CAAT | 68 |
| 3 · alta y borrado de `ESP-BORRAR` | 68 (sube a 69 y vuelve) |
| 4 · alta de operador | 72 |
| 5 · propone perfil | 75 |
| 6 · superadmin acredita | 75 |

Si algún total no cuadra, ahí está el flujo que el espejo no cubre. La sonda
nombra entidad, documento y los dos valores.

**Verde en todo significa que el espejo aguantó los caminos reales, no solo
los del banco local.** Ahí —y no antes— la Etapa 4 tiene una base comprobada
sobre la que mover las lecturas.

## Si lo dejas a medias y sigues otro día

**Sí se puede.** Lo sembrado se queda en pruebas y los totales siguen donde los
dejaste. La sonda del espejo **no exige sello de paridad fresco** —solo lo
imprime—, así que corre igual al día siguiente. Las que sí se niegan a arrancar
con el sello viejo son `01-diagnostico`, `02-sembrar` y `03-flujo-completo`, y
este guion no usa ninguna.

### Para saber dónde te quedaste

En la terminal:

```bash
node -e "import('file:///C:/Users/Usuario/Documents/Flotaapp/pruebas/lib/api.mjs').then(async m=>{
  const A=m.leerAmbientePruebas(),c=m.leerCredenciales();
  const s=new m.Sesion('sa',A); await s.login(c.superadmin.email,c.superadmin.password);
  const {data:v,ok}=await s.select('vigencias','select=entidad_tipo,entidad_id,tipo_documento,estado,fecha_documento,archivo_path&limit=500');
  if(!ok){console.log('  no se pudo leer vigencias');return;}
  const F=['2027-10-20','2027-11-21','2027-12-22'];
  const cam=v.filter(x=>x.entidad_tipo==='camion'), op=v.filter(x=>x.entidad_tipo==='operador');
  const mio=v.filter(x=>x.entidad_tipo==='perfil'&&F.includes(x.fecha_documento));
  const caat=cam.find(x=>x.tipo_documento==='caat'&&x.fecha_documento==='2028-04-14');
  const alta=cam.some(x=>x.fecha_documento==='2027-01-11');
  const di=(b,t)=>console.log('  '+(b?'[hecho]  ':'[falta]  ')+t);
  console.log('
  total de filas en vigencias: '+v.length+'
');
  di(alta, 'paso 1 - alta del camion con las cinco fechas');
  di(!!caat && !!caat.archivo_path, 'paso 2 - CAAT renovado a 2028-04-14 y con archivo');
  di(alta && !cam.some(x=>x.entidad_id==='ESP-BORRAR'), 'paso 3 - ESP-BORRAR dado de alta y borrado (si nunca lo diste de alta esto sale hecho: mira el total)');
  di(op.some(x=>x.fecha_documento==='2026-07-17'), 'paso 4 - alta del operador con el examen medico');
  di(mio.length>0, 'paso 5 - los tres documentos de perfil del guion');
  di(mio.length>0 && mio.every(x=>x.estado==='vigente'), 'paso 6 - y ya estan acreditados');
  console.log('');});"
```

Reconoce cada paso **por las fechas concretas de este guion**, no por la mera
presencia de filas: pruebas ya trae tres documentos de perfil copiados de
producción, y contarlos daría por hechos los pasos 5 y 6 sin haberlos hecho.

**El paso 3 es el único que no se puede distinguir así**, porque termina
borrando su propio rastro: «no hay filas de `ESP-BORRAR`» es lo mismo antes de
empezarlo que después de acabarlo. Si no te acuerdas, míralo por el total — si
va por 68 y los pasos 1 y 2 salen hechos, o no lo has hecho o lo has hecho
entero, y repetirlo no cuesta nada ni deja residuo.

### Lo único que rompe la continuidad

**Que alguien replique producción a pruebas.** La réplica hace
`DROP SCHEMA public CASCADE`, así que se lleva por delante **las cinco
migraciones de H-04 y todo lo que hayas sembrado**. Si pasa, hay que empezar de
cero:

```bash
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260918160000_vigencias_etapa1_crear.sql
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260921120000_vigencias_etapa2_copiar.sql
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260922120000_vigencias_etapa3_doble_escritura.sql
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260922130000_vigencias_espejo_tolerante.sql
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260922140000_vigencias_espejo_borrado.sql
```

Y el total de partida vuelve a ser 63 — aunque puede variar si producción
cambió, así que **vuelve a apuntarlo** en vez de dar por buenos los números de
la tabla.

Lo otro que puede descolocarte es que alguien despliegue cambios de interfaz
que muevan los formularios. Si una etiqueta del guion ya no está donde dice,
avisa antes de improvisar: probablemente el guion haya que corregirlo.

## Después, si quieres dejarlo limpio

Lo sembrado aquí (un camión, un operador, los documentos del perfil) queda en
pruebas. **No hace falta borrarlo**: la siguiente réplica de producción lo
sustituye entero. Y borrar a mano en una base es justo lo que la regla #1 pide
no hacer por costumbre.
