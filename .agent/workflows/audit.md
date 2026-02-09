---
description: Workflow especializado de auditoría total del proyecto
---

# /audit - Auditoría Inteligente

Este workflow ejecuta una auditoría del proyecto, decidiendo el tipo y profundidad según el request.

---

## Paso 1: Clasificar Tipo de Auditoría

Analiza el prompt del usuario y clasifica:

| Tipo | Señales | Protocolo |
|------|---------|-----------|
| `total` | "auditoría completa", "todo el proyecto", "pre-launch", "final" | `/plan/4.0_Auditoria.md` |
| `cambios` | "revisar cambios", "validar antes de push", "lo que acabo de hacer" | `/plan/7.0_Mantenimiento_Auditoria.md` |
| `docs` | "revisar documentación", "sync docs", "actualizar docs" | `/plan/7.1_Mantenimiento_Docs.md` |
| `security` | "seguridad", "vulnerabilidades", "auth", "RBAC" | Auditoría de seguridad específica |
| `performance` | "performance", "optimización", "lento", "web vitals" | Auditoría de performance |

> Si no es claro, asumir `cambios` (la más común en mantenimiento).

---

## Paso 2: Cargar Contexto de Auditoría

### 2.1 Agentes (SIEMPRE cargar)

```
/agents/auditor.md              (protocolo de auditoría)
/agents/tech-lead.md            (estándares técnicos)
```

### 2.2 Agentes Adicionales por Tipo

| Tipo | Agentes adicionales |
|------|---------------------|
| `total` | + security-reviewer, qa-engineer |
| `cambios` | + qa-engineer (si hay tests) |
| `docs` | + technical-writer, project-architect |
| `security` | + security-reviewer, backend-engineer |
| `performance` | + frontend-engineer |

### 2.3 Protocolos

```
SIEMPRE leer:
AI_Development_Rules_And_Best_Practices.md

Según tipo:
- total     → /plan/4.0_Auditoria.md (completo)
- cambios   → /plan/7.0_Mantenimiento_Auditoria.md
- docs      → /plan/7.1_Mantenimiento_Docs.md
- security  → Sección de seguridad de 4.0
- performance → Sección de performance de 4.0
```

### 2.4 Documentación del Proyecto

```
Ejecuta: list_dir en /docs/
Lee: Documentos relevantes para la auditoría
```

---

## Paso 3: Ejecutar Auditoría

### Para `total`

Ejecuta **TODAS** las secciones de `/plan/4.0_Auditoria.md`:

1. ✅ Coherencia Docs ↔ Código
2. ✅ Backlog Completado
3. ✅ Calidad Técnica (build, typecheck, lint, test)
4. ✅ Seguridad
5. ✅ UX / Mobile
6. ✅ Performance
7. ✅ Design System Compliance
8. ✅ PWA Compliance

### Para `cambios`

Ejecuta el checklist de `/plan/7.0_Mantenimiento_Auditoria.md`:

```bash
# Calidad técnica
npm run build
npm run typecheck
npm run lint
npm run test
```

- [ ] Código sigue convenciones
- [ ] Sin código muerto
- [ ] Sin console.log de debug
- [ ] Feature/fix funciona
- [ ] No rompe flujos existentes

### Para `docs`

Ejecuta el protocolo de `/plan/7.1_Mantenimiento_Docs.md`:

1. Leer toda la documentación existente
2. Mapear cambios recientes vs docs
3. Detectar discrepancias
4. Actualizar documentación
5. Sincronizar `/docs` ↔ `/docs/support`

### Para `security`

Enfocarse en:

- [ ] Auth implementado en rutas protegidas
- [ ] RBAC verifica permisos en Server Actions
- [ ] No secrets hardcodeados
- [ ] `.env` en `.gitignore`
- [ ] Inputs validados con Zod
- [ ] Errores no exponen info sensible

### Para `performance`

Enfocarse en:

- [ ] LCP < 2.5s
- [ ] FID < 100ms
- [ ] CLS < 0.1
- [ ] Bundle size razonable
- [ ] Server Components usados correctamente
- [ ] No fetches innecesarios en cliente

---

## Paso 4: Documentar Hallazgos

Para CADA hallazgo encontrado:

```markdown
#### H-XXX: [Título] [SEVERIDAD]
**Qué:** Descripción clara del problema
**Evidencia:** Archivo:línea o captura
**Doc Reference:** Qué documento/sección viola (si aplica)
**Acción:** Issue a crear o fix requerido
```

### Severidades

| Nivel | Significado | Acción |
|-------|-------------|--------|
| 🔴 CRÍTICO | Bloquea deploy, seguridad | Pausar, fix inmediato |
| 🟠 ALTO | Funcionalidad rota | Fix antes de merge |
| 🟡 MEDIO | Desviación de spec | Crear issue |
| 🟢 BAJO | Nice-to-have | Documentar |

---

## Paso 5: Fix y Re-Auditar (si hay hallazgos)

Si se encontraron hallazgos CRÍTICOS o ALTOS:

```
1. Corregir el problema
2. Volver a ejecutar los checks relevantes
3. Verificar que el hallazgo está resuelto
4. Repetir hasta que esté limpio
```

> **Regla**: NO avanzar si hay hallazgos CRÍTICOS sin resolver.

---

## Paso 6: Sincronizar Documentación (si aplica)

Si la auditoría reveló gaps o si se hicieron fixes:

1. Evaluar si los cambios afectan comportamiento documentado
2. Si sí → Actualizar `/docs/` según `/plan/7.1_Mantenimiento_Docs.md`

---

## Paso 7: Emitir Decisión Final

### Si hay hallazgos críticos sin resolver:

```markdown
🔴 PROYECTO REQUIERE CORRECCIONES

Hallazgos pendientes:
- [H-001] [Descripción] [CRÍTICO]
- [H-002] [Descripción] [ALTO]

Acción requerida: Resolver hallazgos antes de continuar
```

### Si no hay hallazgos bloqueantes:

```markdown
✅ AUDITORÍA COMPLETADA

Tipo: [total | cambios | docs | security | performance]
Hallazgos encontrados: X
- Críticos: 0
- Altos: 0
- Medios: X
- Bajos: X

Decisión: [Listo para push | Listo para deploy | Continuar trabajo]

## Documentación
- [x] Actualizada (o N/A)
```

---

## Paso 8: Guardar Evidencia

Para auditorías `total`, guardar reporte en:

```
/docs/99_auditoria_final.md
```

Para auditorías de `cambios`, incluir resumen en el mensaje de entrega.

---

## Diagrama del Flujo

```
┌─────────────────────────────────────────────────────────────┐
│                        /audit                                │
├─────────────────────────────────────────────────────────────┤
│  1. Clasificar      → Tipo de auditoría requerida           │
│  2. Cargar          → Agentes + Protocolos + Docs           │
├─────────────────────────────────────────────────────────────┤
│  3. EJECUTAR        → Checklist según tipo                  │
│  4. DOCUMENTAR      → Hallazgos con severidad               │
├─────────────────────────────────────────────────────────────┤
│  5. FIX (si aplica) → Corregir y re-auditar                 │
│  6. SYNC DOCS       → Actualizar si hubo cambios            │
├─────────────────────────────────────────────────────────────┤
│  7. DECISIÓN        → Continuar / Bloquear / Deploy         │
│  8. EVIDENCIA       → Guardar reporte (si total)            │
└─────────────────────────────────────────────────────────────┘
```

---

## Regla de Oro

> Una auditoría **NO es un resumen**. Debe producir:
> 1. Una **decisión** clara (continuar/pausar/ajustar)
> 2. **Acciones concretas** con responsables
> 3. **Evidencia** para cada hallazgo
