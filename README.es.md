# NIKO-SUN Solar Token

[🇺🇸 English](README.md) | 🇪🇸 Español

---

## 🌐 Contrato Desplegado

| Red | Dirección |
|-----|-----------|
| **Syscoin Testnet** | [`0xA91D0F5ce84f8CbE20443B806ceF8D8116C8CEC8`](https://tanenbaum.io/address/0xA91D0F5ce84f8CbE20443B806ceF8D8116C8CEC8) |

---

## Descripción General

**SolarTokenV3Optimized** es un contrato inteligente ERC-1155 diseñado para tokenizar proyectos de energía solar. Permite la creación de proyectos de inversión, acuñación de tokens, distribución de ingresos y seguimiento transparente de la producción de energía.

## Características

### 🔋 Gestión de Proyectos
- **Crear Proyectos**: Cualquiera puede crear proyectos de inversión en energía solar con parámetros personalizables
- **Metadatos del Proyecto**: Cada proyecto incluye nombre, suministro total, precio por token y requisitos mínimos de compra
- **Control de Estado**: Los creadores pueden activar/desactivar sus proyectos
- **Transferencia de Propiedad**: La propiedad del proyecto puede transferirse a otra dirección

### 💰 Economía de Tokens
- **ERC-1155 Multi-Token**: Cada proyecto tiene su propio ID de token
- **Precios Flexibles**: Precio configurable por token en Wei
- **Compra Mínima**: Cantidad mínima de tokens requerida por transacción
- **Reembolsos Automáticos**: Los pagos excedentes se reembolsan automáticamente

### 📊 Distribución de Ingresos
- **Depositar Ingresos**: Los creadores pueden depositar ingresos de la producción de energía
- **Distribución Justa**: Los ingresos se distribuyen proporcionalmente según la tenencia de tokens
- **Reclamar Recompensas**: Los inversores pueden reclamar recompensas acumuladas en cualquier momento
- **Reclamos por Lote**: Reclamar recompensas de múltiples proyectos en una sola transacción

### ⚡ Seguimiento de Energía
- **Actualizaciones de Energía**: Seguimiento de la energía total producida en kWh
- **Métricas Transparentes**: Visibilidad on-chain de los datos de generación de energía

### 🔒 Características de Seguridad
- **Ownable**: Funciones de administrador restringidas al propietario del contrato
- **Pausable**: Funcionalidad de pausa de emergencia
- **ReentrancyGuard**: Protección contra ataques de reentrada
- **Errores Personalizados**: Manejo de errores eficiente en gas

## Arquitectura del Contrato

```
SolarTokenV3Optimized
├── ERC1155 (Estándar multi-token)
├── Ownable (Control administrativo)
├── Pausable (Parada de emergencia)
└── ReentrancyGuard (Seguridad)
```

## Funciones Principales

| Función | Descripción |
|---------|-------------|
| `createProject()` | Crear un nuevo proyecto solar |
| `mint()` | Comprar tokens de un proyecto |
| `depositRevenue()` | Depositar ingresos para distribución |
| `claimRevenue()` | Reclamar recompensas acumuladas |
| `claimMultipleOptimized()` | Reclamar de múltiples proyectos |
| `withdrawSales()` | Retirar ganancias de ventas (solo creador) |

---

## 🛠️ Desarrollo

### Construido con Foundry

**Foundry es un kit de herramientas rápido, portátil y modular para el desarrollo de aplicaciones Ethereum escrito en Rust.**

Foundry consiste en:

- **Forge**: Framework de testing para Ethereum (similar a Truffle, Hardhat y DappTools).
- **Cast**: Navaja suiza para interactuar con contratos inteligentes EVM, enviar transacciones y obtener datos de la cadena.
- **Anvil**: Nodo local de Ethereum, similar a Ganache o Hardhat Network.
- **Chisel**: REPL de Solidity rápido, utilitario y detallado.

### Documentación

https://book.getfoundry.sh/

### Uso

#### Compilar

```shell
forge build
```

#### Tests

```shell
forge test
```

#### Formatear

```shell
forge fmt
```

#### Snapshots de Gas

```shell
forge snapshot
```

#### Desplegar

```shell
forge script script/DeploySolarToken.s.sol --rpc-url <tu_rpc_url> --private-key <tu_private_key> --broadcast
```

#### Cast

```shell
cast <subcomando>
```

#### Ayuda

```shell
forge --help
anvil --help
cast --help
```

---

## 📄 Licencia

MIT
