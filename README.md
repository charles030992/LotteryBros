# LotteryBros — Pool de lotería multifirma

Estado: en progreso (V1, solo red local de Hardhat)

Contrato inteligente para que un grupo de amigos junte dinero cada mes y compre lotería **sin que nadie pueda mover fondos por su cuenta**: cada paso importante necesita la aprobación de otros miembros.

## Cómo funciona

1. **Contribuir** — cada miembro aporta la cuota mensual exacta (`contribute`).
2. **Aprobar contribuciones** — otros miembros validan que la aportación es real (`approveContribution`). Nadie puede aprobar la suya. Con `requiredApprovals` aprobaciones, queda aprobada.
3. **Proponer una compra** — solo un miembro con alguna contribución aprobada puede proponer comprar lotería (`purchaseLottery`). Proponer **no mueve dinero**.
4. **Aprobar y ejecutar la compra** — otros miembros (no el comprador) aprueban (`approvePurchase`). Cuando hay `requiredApprovals` aprobaciones, cualquier miembro puede ejecutarla (`executePurchase`) y los fondos van al comprador, **una sola vez**.
5. **Cambios de miembros** — añadir o quitar a alguien requiere una propuesta y la aprobación de la mayoría (mitad + 1) (`proposeAddMember`, `proposeRemoveMember`, `approveMemberProposal`).

El contrato usa una guarda de reentrada (`nonReentrant`) en `purchaseLottery` y `executePurchase`.

## Cómo probarlo

Requisitos: Node.js 20+.

```bash
npm install
npx hardhat compile
npx hardhat test
```

Los tests (`test/LotteryPoolV1.test.ts`) cubren contribuciones, aprobaciones, el flujo de compra —incluido que **no se puede cobrar dos veces la misma compra**— y las propuestas de miembros por mayoría.

Despliegue en la red local simulada:

```bash
npx hardhat run scripts/deploy.ts
```

## Limitaciones conocidas

- Solo se ha usado en la red local de Hardhat; no está desplegado en ninguna testnet.
- No hay sorteo ni reparto de premios: el contrato gestiona la caja común y las compras, no el resultado.
- Al quitar a un miembro se marca como no miembro, pero sigue en la lista interna `members`. Por eso la mayoría (mitad + 1) se calcula sobre todos los miembros que ha habido, no solo los actuales.
- No ha sido auditado. No uses este contrato con dinero real.

## Notas

- Hardhat 3 (ESM + TypeScript). Si `npm install` da problemas de dependencias, prueba con `npm install --legacy-peer-deps`.
- `contracts/Counter.sol`, `test/Counter.ts` y `ignition/modules/Counter.ts` son la plantilla inicial de Hardhat.
- El detalle del arreglo de doble pago está en `CHANGES/github-pr.md`.

## Licencia

MIT — ver [LICENSE](./LICENSE).
