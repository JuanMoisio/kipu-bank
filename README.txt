# KipuBank — README

## Descripción

**KipuBank** es un contrato educativo en Solidity que implementa una bóveda simple de ETH por usuario con:

- Depósitos de tokens nativos (ETH).
- Retiros con **tope fijo por transacción** (`WITHDRAW_MAX`, inmutable definido al desplegar).
- **Límite global** de capacidad de operaciones de depósito mediante un contador (`bankCap` = cantidad máxima de depósitos permitidos).
- Contadores globales de **depósitos** y **retiros**.
- Buenas prácticas: errores personalizados, patrón *checks-effects-interactions*, envío nativo seguro y validaciones privadas.

> **Aviso**: contrato con fines educativos. No usar en producción.

---

## Características principales

- `WITHDRAW_MAX` (`immutable`): tope de retiro por transacción fijado al desplegar.
- `bankCap`: máximo de depósitos permitidos (contador de operaciones de depósito).
- Contadores:
  - `transactionsCounter`: total de depósitos.
  - `withdrawalCounter`: total de retiros.

---

## Interfaz pública (resumen)

**Variables de estado**
- `mapping(address => uint256) public balances`
- `uint256 public immutable WITHDRAW_MAX`
- `uint256 public bankCap`
- `uint256 public transactionsCounter`
- `uint256 public withdrawalCounter`

**Eventos**
```solidity
event depositDone(address client, uint256 amount);
event withdrawalDone(address client, uint256 amount);
```

**Errores personalizados**
```solidity
error transactionFailed();
error insufficientBalance(uint256 have, uint256 need);
error capExceeded(uint256 requested, uint256 cap);
error wrongUser(address thief, address victim);
error zeroDeposit();
```

**Funciones**
```solidity
constructor(uint256 capWei, uint256 maxTransactions)
function deposit() external payable
function withdrawal(uint256 value) external
function bankStats() external view returns (uint256 totalDeposits, uint256 totalwithdrawal)
```

**Funciones privadas (ejemplos)**
```solidity
function _depostiRequierements(uint256 value) private view
function _withdrawlRequierements(uint256 value, uint256 cap, uint256 balance) private pure
```

---

## Requisitos

- **Remix + MetaMask** (despliegue rápido)

---

## Cómo interactuar con el contrato

### Remix

- **Deploy**  
  Ingresá los parámetros del constructor y desplegá en Remix con MetaMask (red **Sepolia**):
  - `capWei`: cantidad máxima por **retiro** (en **wei**).
  - `maxTransactions`: cantidad máxima de **depósitos** totales.
  
  **Ejemplo**: `50000, 20` → retiros de hasta **50 000 wei** y hasta **20 depósitos** totales.

- **Depositar**  
  Usá `deposit()` y seteá `Value` en wei (arriba del botón).  
  Actualiza `balances[msg.sender]` y `transactionsCounter`; emite `depositDone`.

- **Retirar**  
  Llamá `withdrawal(value)` (wei).  
  Valida contra `WITHDRAW_MAX` y `balances[msg.sender]`; emite `withdrawalDone`.

- **Ver estadísticas**  
  `bankStats()` devuelve `(totalDeposits, totalwithdrawal)`.

- **Getters útiles**  
  `balances(<address>)`, `WITHDRAW_MAX()`, `bankCap()`, `transactionsCounter()`, `withdrawalCounter()`.

---

## Notas

- Asegurate de compilar con **Solidity 0.8.26** y mantener las mismas opciones si luego vas a verificar en Etherscan.
- Si vas a verificar manualmente, recordá que los argumentos del constructor deben ir **ABI-encoded** y coincidir exactamente con los usados en el despliegue.

---

## Licencia

**MIT**.
