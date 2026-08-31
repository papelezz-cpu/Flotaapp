--
-- PostgreSQL database dump
--

\restrict mqEKP7yMqopT5orJrmeQoXbl1T73zwat0FELOxQXVesT0ZoekyV1hsHi3KKkk9D

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: app_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.app_config (clave, valor, descripcion, actualizado_en) FROM stdin;
version_minima_android	{"url": "https://play.google.com/store/apps/details?id=mx.portgo.app", "version": "0.0.0"}	Versión mínima soportada en Android. Subirla bloquea las anteriores en el arranque.	2026-08-11 16:25:11.371573+00
version_minima_ios	{"url": "https://apps.apple.com/app/portgo", "version": "0.0.0"}	Versión mínima soportada en iOS.	2026-08-11 16:25:11.371573+00
aviso_global	null	Mensaje que la app muestra al arrancar. Formato: {"titulo":"…","mensaje":"…","tipo":"info|alerta"}. null para no mostrar nada.	2026-08-11 16:25:11.371573+00
flags	{}	Interruptores de funciones. Permite enviar código apagado y encenderlo sin publicar una versión.	2026-08-11 16:25:11.371573+00
\.


--
-- Data for Name: catalogos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.catalogos (clave, valor, etiqueta, ayuda, orden, activo, meta) FROM stdin;
plazo_pago	Anticipado	Anticipado	\N	1	t	\N
plazo_pago	Contra entrega	Contra entrega	\N	2	t	\N
plazo_pago	15 días	15 días	\N	3	t	\N
plazo_pago	30 días	30 días	\N	4	t	\N
plazo_pago	45 días	45 días	\N	5	t	\N
plazo_pago	60 días	60 días	\N	6	t	\N
tipo_contenedor	20'	20 pies	\N	1	t	\N
tipo_contenedor	40'	40 pies	\N	2	t	\N
tipo_contenedor	40' HC	40 pies High Cube	\N	3	t	\N
tipo_contenedor	Reefer 20'	Reefer 20 pies	\N	4	t	\N
tipo_contenedor	Reefer 40'	Reefer 40 pies	\N	5	t	\N
tipo_contenedor	Open top	Open top	\N	6	t	\N
tipo_contenedor	Flat rack	Flat rack	\N	7	t	\N
categoria_carga	General	Carga general	Tarimas, cajas, mercancía empacada	1	t	{"campos": ["peso", "tarimas", "refri"]}
categoria_carga	Consolidada	Consolidada	Varios embarques en la misma unidad	2	t	{"campos": ["peso", "tarimas", "bultos", "refri"]}
categoria_carga	Suelta	Carga suelta	Granel, sacos, material sin empacar	3	t	{"campos": ["peso", "refri"]}
categoria_carga	Sobredimensionada	Sobredimensionada	Excede medidas o peso estándar	4	t	{"campos": ["peso", "dim"]}
categoria_carga	Hazmat	Materiales peligrosos	Requiere permiso y unidad certificada	5	t	{"campos": ["peso", "hazmat"]}
categoria_carga	Contenerizada	Contenerizada	Contenedor de 20 o 40 pies	6	t	{"campos": ["contenedores", "refri"]}
tipo_unidad	Camioneta 1.5 ton caja seca	Camioneta 1.5 ton	\N	1	t	\N
tipo_unidad	Camioneta 3.5 ton caja seca	Camioneta 3.5 ton	\N	2	t	\N
tipo_unidad	Rabón	Rabón	\N	3	t	\N
tipo_unidad	Torton caja seca	Torton caja seca	\N	4	t	\N
tipo_unidad	Torton plataforma	Torton plataforma	\N	5	t	\N
tipo_unidad	Full	Full	\N	6	t	\N
tipo_unidad	Full porta contenedor 40/20	Full porta contenedor	\N	7	t	\N
tipo_unidad	Sencillo porta contenedor 40/20	Sencillo porta contenedor	\N	8	t	\N
tipo_unidad	Plataforma de 3 ejes (sobrepeso)	Plataforma 3 ejes	\N	9	t	\N
tipo_unidad	Lowboy	Lowboy / cama baja	\N	10	t	\N
tipo_unidad	HAZMAT	HAZMAT	\N	11	t	\N
tracking_camion	Confirmado	Confirmado	\N	1	t	{"icono": "✅"}
tracking_camion	En camino	En camino al origen	\N	2	t	{"icono": "🚛"}
tracking_camion	En carga	En carga	\N	3	t	{"icono": "⚓"}
tracking_camion	En tránsito	En tránsito	\N	4	t	{"icono": "📍"}
tracking_camion	Entregado	Entregado	\N	5	t	{"icono": "✓"}
tracking_custodio	Confirmado	Confirmado	\N	1	t	{"icono": "✅"}
tracking_custodio	Asignado	Custodio asignado	\N	2	t	{"icono": "👮"}
tracking_custodio	En ruta	En ruta al punto	\N	3	t	{"icono": "🚗"}
tracking_custodio	En servicio	En servicio	\N	4	t	{"icono": "🛡️"}
tracking_custodio	Finalizado	Servicio finalizado	\N	5	t	{"icono": "✓"}
tracking_patio	Confirmado	Confirmado	\N	1	t	{"icono": "✅"}
tracking_patio	Listo	Patio listo	\N	2	t	{"icono": "🏭"}
tracking_patio	Recibido	Vehículo recibido	\N	3	t	{"icono": "🚗"}
tracking_patio	En almacenaje	En almacenaje	\N	4	t	{"icono": "📦"}
tracking_patio	Liberado	Vehículo liberado	\N	5	t	{"icono": "✓"}
tracking_lavado	Confirmado	Confirmado	\N	1	t	{"icono": "✅"}
tracking_lavado	Recibido	Vehículo recibido	\N	2	t	{"icono": "🚗"}
tracking_lavado	En lavado	En proceso de lavado	\N	3	t	{"icono": "🚿"}
tracking_lavado	Control	Control de calidad	\N	4	t	{"icono": "🔍"}
tracking_lavado	Listo	Listo para entrega	\N	5	t	{"icono": "✓"}
\.


--
-- Data for Name: documentos_catalogo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.documentos_catalogo (id, etapa, nombre, descripcion, obligatorio, orden, activo, created_at) FROM stdin;
46a101a9-6090-4f28-9927-436af3563228	ingreso_puerto	Pedimento aduanal pagado	Comprobante de pago del pedimento. Sin él no se libera la mercancía.	t	1	t	2026-08-09 20:50:09.053683+00
3fdd23a4-2272-4564-995b-47acb9dc6a2c	ingreso_puerto	Carta de liberación de la naviera	Autoriza el retiro del contenedor. La emite la naviera al agente aduanal.	t	2	t	2026-08-09 20:50:09.053683+00
53f7e721-69ea-4fe8-82aa-cac0d210408f	ingreso_puerto	BL revalidado	Bill of Lading con la revalidación que transfiere los derechos de la mercancía.	t	3	t	2026-08-09 20:50:09.053683+00
eddea40f-2927-4876-9fce-530923b6f69a	ingreso_puerto	Factura comercial	Factura del proveedor en el extranjero.	t	4	t	2026-08-09 20:50:09.053683+00
7b694bbe-36b8-45d6-aa9f-eb5fcc455389	ingreso_puerto	Packing list	Desglose de la mercancía por bulto.	f	5	t	2026-08-09 20:50:09.053683+00
483ffce0-172b-4056-b2f0-12918833a6f8	ingreso_puerto	Datos del contenedor y sello	Número de contenedor y número de sello o precinto.	t	6	t	2026-08-09 20:50:09.053683+00
97d8c3e4-dadf-44d2-a03b-346ec8ddac52	entrega_vacios	Carta de devolución de la naviera	Indica a qué depósito se devuelve. No es libre: reefer, open top y flat rack regresan al puerto de arribo.	t	1	t	2026-08-09 20:50:09.053683+00
3039dd64-f49f-422f-a682-13caddd6d38a	entrega_vacios	Comprobante de libre adeudo	Que no haya demoras pendientes de pago; si las hay, el comprobante de pago.	t	2	t	2026-08-09 20:50:09.053683+00
9fa38030-6f3c-4669-9c26-6820f933fdbf	entrega_vacios	Datos del depósito asignado	Nombre, dirección y horario del patio de vacíos.	t	3	t	2026-08-09 20:50:09.053683+00
\.


--
-- PostgreSQL database dump complete
--

\unrestrict mqEKP7yMqopT5orJrmeQoXbl1T73zwat0FELOxQXVesT0ZoekyV1hsHi3KKkk9D

