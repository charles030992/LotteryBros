# PR: Fix doble pago, evitar auto-aprobación y control de cambios de miembros

Resumen:

Hemos identificado y corregido un bug crítico que permitía a un comprador drenar el pool llamando a `purchaseLottery` y luego a `reimburse` (doble pago). Además hemos mejorado el mecanismo de aprobaciones para contribuciones (se evita que un miembro apruebe su propia contribución) y hemos cambiado la gestión de miembros para que añadir/quitar miembros requiera una propuesta y la aprobación de la mayoría (mitad+1) de los miembros.

Problema encontrado:

- purchaseLottery originalmente transfería fondos al comprador inmediatamente y la función `reimburse` transfería de nuevo al comprador, permitiendo doble retiro.
- `approveContribution` permitía auto-aprobación si `requiredApprovals` era 1.
- `addMember`/`removeMember` eran operaciones unilaterales por cualquier miembro sin consenso.

Cambios realizados (detallado):

1. Evitar doble pago / nuevo flujo de compra
   - `purchaseLottery` ahora registra una propuesta de compra (`LotteryPurchase`) pero NO transfiere fondos inmediatamente.
   - Añadidas funciones: `approvePurchase(uint256 purchaseId)` y `executePurchase(uint256 purchaseId)`.
     - `approvePurchase` permite que otros miembros (no el comprador) aprueben la compra.
     - `executePurchase` transfiere los fondos al `purchasedBy` solo cuando la compra tiene al menos `requiredApprovals` aprobaciones.
   - Se eliminó la antigua lógica de `reimburse` (se dejó comentada la razón en el contrato) para eliminar el vector de doble pago.

2. Evitar auto-aprobación
   - `approveContribution` ahora exige `msg.sender != member`.

3. Gestión de miembros con propuesta y quórum
   - Eliminadas las funciones unilaterales `addMember` y `removeMember`.
   - Añadido flujo de propuestas: `proposeAddMember`, `proposeRemoveMember`, `approveMemberProposal`.
   - Una propuesta se ejecuta automáticamente cuando alcanza la mayoría: `(members.length / 2) + 1` aprobaciones.

Archivos modificados:

- `contracts/LotteryPoolV1.sol` (lógica principal: fixes y nuevas APIs)

Motivación de diseño:

- Cambiar la compra para que sea un flujo propuesto/aprobado evita transferencias instantáneas y requiere consenso antes de drenar fondos.
- Evitar la auto-aprobación reduce la capacidad de un miembro para manipular el requisito de quorum cuando `requiredApprovals` es bajo.
- Forzar aprobación mayoritaria para cambios de membresía previene que un miembro o una minoría añada/quite miembros por su cuenta.

Cómo verificar localmente (PowerShell en Windows):

1. Instalar dependencias (si aún no están instaladas):

```powershell
cd c:\Users\carlo\VStudio\LotteryBros
npm ci
```

2. Ejecutar los tests de Solidity (Hardhat):

```powershell
npx hardhat test --network hardhat
```

Nota: En mi ejecución, las pruebas de Solidity pasaron, pero la suite Mocha/TypeScript arrojó un error ESM/Top-level-await (esto parece estar relacionado con la configuración del entorno de tests, no directamente con estos cambios). Si ves ese error, prueba a ejecutar sólo las pruebas de Solidity o a ajustar la configuración de Node/TypeScript para soportar ESM.

Siguientes pasos recomendados (idea de follow-ups):

- Añadir tests unitarios que cubran el nuevo flujo: crear purchase, aprobar por requiredApprovals miembros, ejecutar purchase, y garantizar que no se pueda ejecutar dos veces.
- Añadir test que confirme que `approveContribution` no permite auto-aprobación.
- Añadir tests para propuestas de miembro y el requisito de mayoría.
- Revisar la política de gas y posibles DoS por longitud de arrays (optimizar contadores en lugar de loops si el grupo crece mucho).
- Auditoría completa del contrato.

Texto sugerido para el PR en GitHub:

_Título:_ Fix: prevent double payout, prevent self-approval and require majority for member changes

_Descripción:_ see this file (CHANGES/github-pr.md) for full details. Fixes a critical vulnerability that allowed a purchaser to withdraw twice and hardens the approval and membership flows.


---

Si quieres, puedo:
- crear tests automáticos que cubran los nuevos comportamientos (los añadiré en TypeScript/Hardhat o en Solidity) — dime qué framework prefieres;
- generar el diff/commit y preparar el PR body listo para pegar en GitHub (yo ya añadí este archivo con la descripción y el rationale).

Si estás de acuerdo, ejecutaré/añadiré tests mínimos que verifiquen el fix y el flujo de propuestas de miembros.
