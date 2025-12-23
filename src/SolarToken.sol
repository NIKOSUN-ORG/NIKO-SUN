// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // Mucho más ligero que AccessControl
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title NiKoSun
 * @author NIKO-SUN
 * @notice Sistema de tokenización de proyectos solares con distribución proporcional de ingresos
 * @dev Implementa ERC-1155 para múltiples proyectos en un solo contrato
 * @dev Características: compra de tokens, rewards proporcionales, transferencias, paginación
 * @dev SEGURIDAD: ReentrancyGuard, Pausable, validaciones exhaustivas
 */
contract NiKoSun is ERC1155, Ownable, Pausable, ReentrancyGuard {
    using Strings for uint256;

    // ========================================
    // CONSTANTES
    // ========================================

    uint256 private constant PRECISION = 1e18;

    // Logo IPFS para todos los tokens del proyecto
    string private constant LOGO_IPFS =
        "https://cyan-acceptable-echidna-172.mypinata.cloud/ipfs/bafkreihcpqm4pxw7unbejavgmhbofoxqsndnhn54segnufl7vcwm6fdwjy";

    // ========================================
    // ESTRUCTURAS
    // ========================================

    struct Project {
        address creator;
        uint96 totalSupply;
        uint96 minted;
        uint96 minPurchase;
        uint128 priceWei;
        uint64 createdAt;
        bool active;
        uint128 totalEnergyKwh;
        uint48 reserved1;
        uint128 totalRevenue;
        uint128 reserved2;
        uint256 rewardPerTokenStored;
    }

    struct ProjectMetadata {
        string name;
    }

    struct InvestorPosition {
        uint256 projectId;
        uint256 tokenBalance;
        uint256 claimableAmount;
        uint256 totalClaimed;
    }

    // ========================================
    // ESTADO
    // ========================================

    uint256 private _nextProjectId = 1;
    string private _baseMetadataURI;

    mapping(uint256 => Project) public projects;
    mapping(uint256 => ProjectMetadata) public metadata;
    mapping(uint256 => uint256) public projectSalesBalance;
    mapping(uint256 => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(uint256 => mapping(address => uint256)) public pendingRewards;
    mapping(uint256 => mapping(address => uint256)) public totalUserClaimed;

    // Mapping para listar proyectos por creador (O(1) lookup)
    mapping(address => uint256[]) private _userProjects;

    // Acumulador global de ventas para O(1) en rescueDust
    uint256 private _totalSalesBalance;

    // ========================================
    // EVENTOS
    // ========================================
    /**
     * @notice Eventos optimizados para indexación eficiente
     * @dev Máximo 3 indexed parameters por evento
     * @dev Se priorizan addresses e IDs sobre timestamps y amounts
     * @dev Los timestamps se obtienen del bloque, no necesitan indexación
     */
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed creator,
        string name,
        uint96 totalSupply,
        uint128 priceWei,
        uint96 minPurchase,
        uint64 timestamp
    );
    event TokensMinted(
        uint256 indexed projectId,
        address indexed buyer,
        uint96 amount,
        uint256 totalPaid,
        uint64 timestamp
    );
    event RevenueDeposited(
        uint256 indexed projectId,
        address indexed depositor,
        uint256 amount,
        uint128 energyKwh,
        uint256 newRewardPerToken,
        uint64 timestamp
    );
    event RevenueClaimed(
        uint256 indexed projectId,
        address indexed investor,
        uint256 amount,
        uint256 totalClaimed,
        uint64 timestamp
    );
    event SalesWithdrawn(
        uint256 indexed projectId,
        address indexed recipient,
        uint256 amount,
        uint64 timestamp
    );
    event EnergyUpdated(
        uint256 indexed projectId,
        uint128 energyDelta,
        uint128 totalEnergy,
        uint64 timestamp
    );
    event EnergySet(
        uint256 indexed projectId,
        uint128 previousEnergy,
        uint128 newEnergy,
        string reason,
        uint64 timestamp
    );
    event ProjectStatusChanged(
        uint256 indexed projectId,
        bool indexed active,
        uint64 timestamp
    );
    event ProjectOwnershipTransferred(
        uint256 indexed projectId,
        address indexed previousCreator,
        address indexed newCreator,
        uint64 timestamp
    );
    event TransferExecuted(
        address indexed from,
        address indexed to,
        uint256 indexed projectId,
        uint256 amount,
        uint64 timestamp
    );
    event DustRescued(
        address indexed recipient,
        uint256 amount,
        uint64 timestamp
    );

    // ========================================
    // ERRORES
    // ========================================
    error InvalidSupply();
    error InvalidPrice();
    error InvalidMinPurchase();
    error InvalidCreator();
    error ProjectNotActive();
    error ProjectNotFound();
    error BelowMinimumPurchase(uint96 minimum);
    error InsufficientSupply();
    error InsufficientPayment();
    error RefundFailed();
    error NoFundsDeposited();
    error NothingToClaim();
    error ClaimTransferFailed();
    error InvalidAmount();
    error InsufficientBalance();
    error WithdrawFailed();
    error NoTokensMinted();
    error Unauthorized();
    error OnlyProjectCreator();
    error RewardIncreaseTooSmall();
    error BatchSizeTooLarge();

    // ========================================
    // MODIFICADORES
    // ========================================

    modifier onlyProjectCreator(uint256 projectId) {
        if (msg.sender != projects[projectId].creator)
            revert OnlyProjectCreator();
        _;
    }

    modifier onlyProjectCreatorOrAdmin(uint256 projectId) {
        // En lugar de checkear rol ADMIN, checkeamos owner()
        if (
            msg.sender != projects[projectId].creator && msg.sender != owner()
        ) {
            revert Unauthorized();
        }
        _;
    }

    // ========================================
    // CONSTRUCTOR & ADMIN
    // ========================================

    /**
     * @notice Inicializa el contrato SolarToken con ERC1155
     * @dev Establece el deployer como owner inicial
     */
    constructor() ERC1155("") Ownable(msg.sender) {}

    /**
     * @notice Establece la URI base para los metadatos de los proyectos
     * @dev Solo puede ser llamado por el owner del contrato
     * @param newBaseURI Nueva URI base (ej: "https://api.example.com/metadata/")
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseMetadataURI = newBaseURI;
    }

    /**
     * @notice Retorna la URI completa del metadata para un proyecto
     * @dev Genera un Data URI con JSON embebido onchain (no requiere servidor externo)
     * @dev Versión simplificada para evitar "Stack too deep"
     * @param projectId ID del proyecto
     * @return URI completa del metadata en formato data:application/json;base64
     */
    function uri(
        uint256 projectId
    ) public view override returns (string memory) {
        if (projects[projectId].creator == address(0)) revert ProjectNotFound();

        string memory projectName = metadata[projectId].name;
        
        // Nombre del token simplificado
        string memory tokenName = bytes(projectName).length > 0
            ? string(abi.encodePacked(projectName, " #", projectId.toString()))
            : string(abi.encodePacked("NikoSolarID", projectId.toString()));

        // JSON minimalista para evitar stack too deep
        string memory json = string(
            abi.encodePacked(
                '{"name":"',
                tokenName,
                '","description":"Solar energy investment token. Powered by NiKoSun.","image":"',
                LOGO_IPFS,
                '"}'
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(bytes(json))
                )
            );
    }

    // ========================================
    // CREACIÓN DE PROYECTOS
    // ========================================

    /**
     * @notice Crea un nuevo proyecto solar
     * @dev El msg.sender se convierte en el creator del proyecto
     * @param projectName Nombre del proyecto
     * @param totalSupply Cantidad total de tokens disponibles
     * @param priceWei Precio por token en wei
     * @param minPurchase Cantidad mínima de tokens por compra
     * @return projectId ID del proyecto creado
     */
    function createProject(
        string calldata projectName,
        uint96 totalSupply,
        uint128 priceWei,
        uint96 minPurchase
    ) external returns (uint256 projectId) {
        projectId = _createProjectLogic(
            msg.sender,
            projectName,
            totalSupply,
            priceWei,
            minPurchase
        );
    }

    /**
     * @notice Crea un proyecto en nombre de otro usuario (solo owner)
     * @dev Permite al admin crear proyectos para otros usuarios
     * @param creator Dirección que será el creator del proyecto
     * @param projectName Nombre del proyecto
     * @param totalSupply Cantidad total de tokens disponibles
     * @param priceWei Precio por token en wei
     * @param minPurchase Cantidad mínima de tokens por compra
     * @return projectId ID del proyecto creado
     */
    function createProjectFor(
        address creator,
        string calldata projectName,
        uint96 totalSupply,
        uint128 priceWei,
        uint96 minPurchase
    ) external onlyOwner returns (uint256 projectId) {
        if (creator == address(0)) revert InvalidCreator();
        projectId = _createProjectLogic(
            creator,
            projectName,
            totalSupply,
            priceWei,
            minPurchase
        );
    }

    /**
     * @dev Lógica interna compartida para crear proyectos
     * @dev Valida parámetros, crea el proyecto y emite evento
     */
    function _createProjectLogic(
        address creator,
        string calldata projectName,
        uint96 totalSupply,
        uint128 priceWei,
        uint96 minPurchase
    ) internal returns (uint256 projectId) {
        if (totalSupply == 0) revert InvalidSupply();
        if (priceWei == 0) revert InvalidPrice();
        if (minPurchase == 0 || minPurchase > totalSupply)
            revert InvalidMinPurchase();

        projectId = _nextProjectId++;

        projects[projectId] = Project({
            creator: creator,
            totalSupply: totalSupply,
            minted: 0,
            minPurchase: minPurchase,
            priceWei: priceWei,
            createdAt: uint64(block.timestamp),
            active: true,
            totalEnergyKwh: 0,
            reserved1: 0,
            totalRevenue: 0,
            reserved2: 0,
            rewardPerTokenStored: 0
        });

        metadata[projectId] = ProjectMetadata({name: projectName});

        // Agregar proyecto al array del creador para consulta eficiente O(1)
        _userProjects[creator].push(projectId);

        emit ProjectCreated(
            projectId,
            creator,
            projectName,
            totalSupply,
            priceWei,
            minPurchase,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Transfiere la propiedad de un proyecto a otro usuario
     * @dev Solo puede ser llamado por el creator actual del proyecto
     * @param projectId ID del proyecto
     * @param newCreator Nueva dirección que será el creator
     */
    function transferProjectOwnership(
        uint256 projectId,
        address newCreator
    ) external onlyProjectCreator(projectId) {
        if (newCreator == address(0)) revert InvalidCreator();
        address previousCreator = projects[projectId].creator;
        projects[projectId].creator = newCreator;

        // Actualizar arrays de proyectos por usuario
        _removeProjectFromUser(previousCreator, projectId);
        _userProjects[newCreator].push(projectId);

        emit ProjectOwnershipTransferred(
            projectId,
            previousCreator,
            newCreator,
            uint64(block.timestamp)
        );
    }

    /**
     * @dev Función interna para remover un proyecto del array de un usuario
     * @param user Dirección del usuario
     * @param projectId ID del proyecto a remover
     */
    function _removeProjectFromUser(address user, uint256 projectId) internal {
        uint256[] storage userProjects = _userProjects[user];
        uint256 length = userProjects.length;

        for (uint256 i = 0; i < length; i++) {
            if (userProjects[i] == projectId) {
                // Mover el último elemento a esta posición y reducir el array
                userProjects[i] = userProjects[length - 1];
                userProjects.pop();
                break;
            }
        }
    }

    /**
     * @notice Activa o desactiva un proyecto
     * @dev Solo el creator puede cambiar el estado. Proyectos inactivos no aceptan compras ni deposits
     * @param projectId ID del proyecto
     * @param active true para activar, false para desactivar
     */
    function setProjectStatus(
        uint256 projectId,
        bool active
    ) external onlyProjectCreator(projectId) {
        if (projects[projectId].createdAt == 0) revert ProjectNotFound();
        projects[projectId].active = active;
        emit ProjectStatusChanged(projectId, active, uint64(block.timestamp));
    }

    // ========================================
    // PÚBLICO: COMPRA DE TOKENS
    // ========================================

    /**
     * @notice Compra tokens de un proyecto
     * @dev Requiere enviar ETH suficiente. Devuelve el exceso automáticamente
     * @param projectId ID del proyecto
     * @param amount Cantidad de tokens a comprar
     */
    function mint(
        uint256 projectId,
        uint96 amount
    ) external payable nonReentrant whenNotPaused {
        Project storage project = projects[projectId];

        if (!project.active) revert ProjectNotActive();
        if (amount < project.minPurchase)
            revert BelowMinimumPurchase(project.minPurchase);
        if (project.minted + amount > project.totalSupply)
            revert InsufficientSupply();

        uint256 totalPrice = uint256(project.priceWei) * uint256(amount);
        if (msg.value < totalPrice) revert InsufficientPayment();

        project.minted += amount;
        projectSalesBalance[projectId] += totalPrice;
        _totalSalesBalance += totalPrice;

        _mint(msg.sender, projectId, amount, "");

        if (msg.value > totalPrice) {
            uint256 refund = msg.value - totalPrice;
            (bool success, ) = msg.sender.call{value: refund}("");
            if (!success) revert RefundFailed();
        }

        emit TokensMinted(
            projectId,
            msg.sender,
            amount,
            totalPrice,
            uint64(block.timestamp)
        );
    }

    // ========================================
    // GESTIÓN Y REWARDS
    // ========================================

    /**
     * @notice Deposita ingresos para distribuir entre holders del proyecto
     * @dev El depósito debe ser suficiente para generar al menos 1 wei de reward por token
     * @dev Los rewards en proyectos inactivos NO se pueden depositar (requiere active=true)
     * @param projectId ID del proyecto
     * @param energyKwhDelta Incremento de energía generada en kWh
     */
    function depositRevenue(
        uint256 projectId,
        uint128 energyKwhDelta
    ) external payable onlyProjectCreatorOrAdmin(projectId) {
        Project storage project = projects[projectId];
        if (!project.active) revert ProjectNotActive();
        if (msg.value == 0) revert NoFundsDeposited();
        if (project.minted == 0) revert NoTokensMinted();

        uint256 rewardIncrease = (msg.value * PRECISION) / project.minted;
        // Validar que el depósito sea suficiente para generar rewards
        if (rewardIncrease == 0) revert RewardIncreaseTooSmall();
        project.rewardPerTokenStored += rewardIncrease;
        project.totalRevenue += uint128(msg.value);

        if (energyKwhDelta > 0) {
            project.totalEnergyKwh += energyKwhDelta;
        }

        emit RevenueDeposited(
            projectId,
            msg.sender,
            msg.value,
            energyKwhDelta,
            project.rewardPerTokenStored,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Incrementa la energía total generada por el proyecto
     * @dev Solo creator o admin. La energía se acumula (no se sobrescribe)
     * @param projectId ID del proyecto
     * @param energyKwhDelta Incremento de energía en kWh
     */
    function updateEnergy(
        uint256 projectId,
        uint128 energyKwhDelta
    ) external onlyProjectCreatorOrAdmin(projectId) {
        Project storage project = projects[projectId];
        if (!project.active) revert ProjectNotActive();
        project.totalEnergyKwh += energyKwhDelta;
        emit EnergyUpdated(
            projectId,
            energyKwhDelta,
            project.totalEnergyKwh,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Establece el valor absoluto de energía generada (solo para correcciones)
     * @dev Requiere permisos de creator o admin. Usar con precaución.
     * @param projectId ID del proyecto
     * @param newTotalEnergy Nuevo valor total de energía en kWh
     * @param reason Motivo de la corrección (para auditoría on-chain)
     */
    function setEnergy(
        uint256 projectId,
        uint128 newTotalEnergy,
        string calldata reason
    ) external onlyProjectCreatorOrAdmin(projectId) {
        Project storage project = projects[projectId];
        if (!project.active) revert ProjectNotActive();

        uint128 previousEnergy = project.totalEnergyKwh;
        project.totalEnergyKwh = newTotalEnergy;

        emit EnergySet(
            projectId,
            previousEnergy,
            newTotalEnergy,
            reason,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Retira fondos de ventas del proyecto
     * @dev Solo el creator puede retirar. Fondos provienen de compras de tokens
     * @param projectId ID del proyecto
     * @param recipient Dirección que recibirá los fondos
     * @param amount Cantidad de ETH a retirar en wei
     */
    function withdrawSales(
        uint256 projectId,
        address recipient,
        uint256 amount
    ) external onlyProjectCreator(projectId) nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (amount > projectSalesBalance[projectId])
            revert InsufficientBalance();

        projectSalesBalance[projectId] -= amount;
        _totalSalesBalance -= amount;

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert WithdrawFailed();

        emit SalesWithdrawn(
            projectId,
            recipient,
            amount,
            uint64(block.timestamp)
        );
    }

    /**
     * @dev Actualiza los rewards pendientes de un inversor antes de transferencias
     * @param projectId ID del proyecto
     * @param investor Dirección del inversor
     */
    function _updateRewards(uint256 projectId, address investor) internal {
        Project storage project = projects[projectId];
        uint256 balance = balanceOf(investor, projectId);
        if (balance > 0) {
            uint256 rewardPerTokenDelta = project.rewardPerTokenStored -
                userRewardPerTokenPaid[projectId][investor];
            uint256 earned = (balance * rewardPerTokenDelta) / PRECISION;
            if (earned > 0) {
                pendingRewards[projectId][investor] += earned;
            }
        }
        userRewardPerTokenPaid[projectId][investor] = project
            .rewardPerTokenStored;
    }

    /**
     * @notice Calcula el monto total de rewards reclamables por un inversor
     * @dev Incluye rewards pendientes + rewards no actualizados
     * @param projectId ID del proyecto
     * @param investor Dirección del inversor
     * @return claimable Cantidad de ETH reclamable en wei
     */
    function getClaimableAmount(
        uint256 projectId,
        address investor
    ) public view returns (uint256 claimable) {
        Project storage project = projects[projectId];
        uint256 balance = balanceOf(investor, projectId);
        claimable = pendingRewards[projectId][investor];
        if (balance > 0) {
            uint256 rewardPerTokenDelta = project.rewardPerTokenStored -
                userRewardPerTokenPaid[projectId][investor];
            uint256 earned = (balance * rewardPerTokenDelta) / PRECISION;
            claimable += earned;
        }
    }

    /**
     * @notice Reclama los rewards pendientes de un proyecto
     * @dev Los rewards de proyectos INACTIVOS SÍ se pueden reclamar
     * @dev Los tokens en proyectos inactivos siguen acumulando rewards previamente depositados
     * @param projectId ID del proyecto del cual reclamar rewards
     */
    function claimRevenue(uint256 projectId) external nonReentrant {
        _claimRevenueLogic(projectId, msg.sender);
    }

    /**
     * @notice Reclama rewards de múltiples proyectos en una sola transacción
     * @dev Limitado a 100 proyectos por llamada para evitar DoS por gas
     * @dev Los rewards de proyectos inactivos SÍ se pueden reclamar
     * @param projectIds Array de IDs de proyectos (máx 100)
     */
    function claimMultiple(
        uint256[] calldata projectIds
    ) external nonReentrant {
        if (projectIds.length > 100) revert BatchSizeTooLarge();

        uint256 totalClaim = 0;
        for (uint256 i = 0; i < projectIds.length; i++) {
            totalClaim += _claimRevenueLogicInternal(projectIds[i], msg.sender);
        }
        if (totalClaim == 0) revert NothingToClaim();

        // Transferir todos los rewards acumulados en una sola transaccion
        (bool success, ) = msg.sender.call{value: totalClaim}("");
        if (!success) revert ClaimTransferFailed();
    }

    /**
     * @dev Helper interno para claim de un solo proyecto con transferencia
     * @param projectId ID del proyecto
     * @param user Dirección del usuario
     */
    function _claimRevenueLogic(uint256 projectId, address user) internal {
        uint256 claimable = _claimRevenueLogicInternal(projectId, user);
        if (claimable == 0) revert NothingToClaim();
        // Transferencia individual
        (bool success, ) = user.call{value: claimable}("");
        if (!success) revert ClaimTransferFailed();
    }

    /**
     * @dev Lógica interna de claim que actualiza estado y retorna monto
     * @param projectId ID del proyecto
     * @param user Dirección del usuario
     * @return Monto reclamado en wei
     */
    function _claimRevenueLogicInternal(
        uint256 projectId,
        address user
    ) internal returns (uint256) {
        _updateRewards(projectId, user);
        uint256 claimable = pendingRewards[projectId][user];
        if (claimable > 0) {
            pendingRewards[projectId][user] = 0;
            totalUserClaimed[projectId][user] += claimable;
            emit RevenueClaimed(
                projectId,
                user,
                claimable,
                totalUserClaimed[projectId][user],
                uint64(block.timestamp)
            );
            return claimable;
        }
        return 0;
    }

    // ========================================
    // VIEW FUNCTIONS & ADMIN
    // ========================================

    /**
     * @notice Obtiene información completa de un proyecto
     * @param projectId ID del proyecto
     * @return project Datos del proyecto
     * @return meta Metadata del proyecto (nombre)
     * @return salesBalance Balance de ventas pendiente de retiro
     * @return availableSupply Tokens disponibles para compra
     */
    function getProject(
        uint256 projectId
    )
        external
        view
        returns (
            Project memory project,
            ProjectMetadata memory meta,
            uint256 salesBalance,
            uint256 availableSupply
        )
    {
        project = projects[projectId];
        meta = metadata[projectId];
        salesBalance = projectSalesBalance[projectId];
        availableSupply = project.totalSupply - project.minted;
    }

    /**
     * @notice Retorna el creator de un proyecto
     * @param projectId ID del proyecto
     * @return Dirección del creator
     */
    function getProjectCreator(
        uint256 projectId
    ) external view returns (address) {
        return projects[projectId].creator;
    }

    /**
     * @notice Verifica si una dirección es el creator del proyecto
     * @param projectId ID del proyecto
     * @param account Dirección a verificar
     * @return true si es el creator, false en caso contrario
     */
    function isProjectCreator(
        uint256 projectId,
        address account
    ) external view returns (bool) {
        return projects[projectId].creator == account;
    }

    /**
     * @notice Obtiene el portfolio de un inversor
     * @dev Limitado a 100 proyectos para evitar DoS. Para más, usar getInvestorPortfolioPaginated
     * @param investor Dirección del inversor
     * @param projectIds Array de IDs de proyectos
     * @return positions Array de posiciones del inversor
     */
    function getInvestorPortfolio(
        address investor,
        uint256[] calldata projectIds
    ) external view returns (InvestorPosition[] memory positions) {
        if (projectIds.length > 100) revert InvalidAmount(); // Límite de 100 proyectos

        positions = new InvestorPosition[](projectIds.length);
        for (uint256 i = 0; i < projectIds.length; i++) {
            uint256 pid = projectIds[i];
            positions[i] = InvestorPosition({
                projectId: pid,
                tokenBalance: balanceOf(investor, pid),
                claimableAmount: getClaimableAmount(pid, investor),
                totalClaimed: totalUserClaimed[pid][investor]
            });
        }
    }

    /**
     * @notice Obtiene el portfolio con paginación para portfolios grandes
     * @dev Permite consultar portfolios de cualquier tamaño usando paginación
     * @param investor Dirección del inversor
     * @param projectIds Array completo de IDs de proyectos
     * @param offset Índice de inicio (0-based)
     * @param limit Cantidad máxima de resultados (máx 100)
     * @return positions Array de posiciones (puede ser menor que limit si se alcanza el final)
     * @return total Total de proyectos en el array original
     * @return hasMore Si hay más resultados disponibles
     */
    function getInvestorPortfolioPaginated(
        address investor,
        uint256[] calldata projectIds,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (
            InvestorPosition[] memory positions,
            uint256 total,
            bool hasMore
        )
    {
        if (limit > 100) revert InvalidAmount(); // Máximo 100 por página

        total = projectIds.length;

        // Calcular el tamaño real del resultado
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        // Si offset está fuera de rango, devolver array vacío
        if (offset >= total) {
            return (new InvestorPosition[](0), total, false);
        }

        uint256 resultSize = end - offset;
        positions = new InvestorPosition[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            uint256 pid = projectIds[offset + i];
            positions[i] = InvestorPosition({
                projectId: pid,
                tokenBalance: balanceOf(investor, pid),
                claimableAmount: getClaimableAmount(pid, investor),
                totalClaimed: totalUserClaimed[pid][investor]
            });
        }

        hasMore = end < total;
    }

    /**
     * @notice Retorna el balance de ventas de un proyecto
     * @param projectId ID del proyecto
     * @return Balance disponible para retiro por el creator en wei
     */
    function getSalesBalance(
        uint256 projectId
    ) external view returns (uint256) {
        return projectSalesBalance[projectId];
    }

    /**
     * @notice Retorna el balance total de ETH del contrato
     * @return Balance total del contrato en wei
     */
    function getTotalBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Retorna el próximo ID de proyecto a crear
     * @return ID que tendrá el próximo proyecto creado
     */
    function nextProjectId() external view returns (uint256) {
        return _nextProjectId;
    }

    // ========================================
    // CONSULTA DE PROYECTOS POR USUARIO
    // ========================================

    /**
     * @notice Obtiene todos los IDs de proyectos creados por un usuario
     * @dev Consulta O(1) gracias al mapping _userProjects
     * @param user Dirección del usuario
     * @return projectIds Array de IDs de proyectos del usuario
     */
    function getUserProjects(
        address user
    ) external view returns (uint256[] memory) {
        return _userProjects[user];
    }

    /**
     * @notice Obtiene la cantidad de proyectos creados por un usuario
     * @param user Dirección del usuario
     * @return count Número de proyectos
     */
    function getUserProjectsCount(
        address user
    ) external view returns (uint256) {
        return _userProjects[user].length;
    }

    /**
     * @notice Obtiene proyectos del usuario con paginación
     * @dev Útil cuando un usuario tiene muchos proyectos
     * @param user Dirección del usuario
     * @param offset Índice de inicio
     * @param limit Cantidad máxima de resultados (máx 50)
     * @return projectIds Array de IDs de proyectos
     * @return total Total de proyectos del usuario
     * @return hasMore Si hay más proyectos disponibles
     */
    function getUserProjectsPaginated(
        address user,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory projectIds, uint256 total, bool hasMore)
    {
        if (limit > 50) revert InvalidAmount(); // Máximo 50 por página

        uint256[] storage userProjects = _userProjects[user];
        total = userProjects.length;

        // Si offset está fuera de rango, devolver array vacío
        if (offset >= total) {
            return (new uint256[](0), total, false);
        }

        uint256 end = offset + limit > total ? total : offset + limit;
        uint256 size = end - offset;

        projectIds = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            projectIds[i] = userProjects[offset + i];
        }

        hasMore = end < total;
    }

    /**
     * @notice Pausa el contrato (solo owner)
     * @dev Bloquea mint y transferTokens. Los claims siguen funcionando
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Despausa el contrato (solo owner)
     * @dev Reactiva las funciones bloqueadas por pause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ========================================
    // RESCUE FUNCTIONS
    // ========================================

    /**
     * @notice Permite al owner recuperar ETH residual (dust) por redondeo
     * @dev O(1) - usa _totalSalesBalance acumulador en lugar de iterar
     * @dev Solo puede retirar el exceso que no está asignado a ventas
     * @dev El dust se acumula por la división entera en rewardPerTokenStored
     * @param recipient Dirección que recibirá el dust
     */
    function rescueDust(address recipient) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidCreator();

        // O(1) - Usamos el acumulador en lugar de iterar sobre proyectos
        uint256 contractBalance = address(this).balance;
        if (contractBalance <= _totalSalesBalance) {
            revert NothingToClaim();
        }

        uint256 dust = contractBalance - _totalSalesBalance;

        (bool success, ) = recipient.call{value: dust}("");
        if (!success) revert WithdrawFailed();

        emit DustRescued(recipient, dust, uint64(block.timestamp));
    }

    /**
     * @notice Obtiene el balance total de ventas acumulado
     * @dev O(1) getter para el acumulador _totalSalesBalance
     * @return Total de ventas pendientes de retiro en todos los proyectos
     */
    function getTotalSalesBalance() external view returns (uint256) {
        return _totalSalesBalance;
    }

    // ========================================
    // TRANSFERENCIAS PÚBLICAS CON LOGGING MEJORADO
    // ========================================

    /**
     * @notice Transferir tokens con logging mejorado para diagnóstico
     * @dev Wrapper sobre safeTransferFrom con eventos adicionales
     * @notice La actualizacion de rewards se hace automaticamente en _update()
     */
    function transferTokens(
        address to,
        uint256 projectId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        if (to == address(0)) revert InvalidCreator();
        if (amount == 0) revert InvalidAmount();
        if (projects[projectId].createdAt == 0) revert ProjectNotFound();
        if (balanceOf(msg.sender, projectId) < amount)
            revert InsufficientBalance();

        // Realizar la transferencia - _update() maneja los rewards automaticamente
        safeTransferFrom(msg.sender, to, projectId, amount, "");

        emit TransferExecuted(
            msg.sender,
            to,
            projectId,
            amount,
            uint64(block.timestamp)
        );
    }

    // ========================================
    // OVERRIDES
    // ========================================

    /**
     * @dev Hook interno de ERC1155 que se ejecuta en todas las transferencias
     * @dev Actualiza los rewards pendientes antes de modificar balances
     * @param from Dirección origen (address(0) en mint)
     * @param to Dirección destino (address(0) en burn)
     * @param ids Array de IDs de proyectos
     * @param values Array de cantidades correspondientes
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {
        // Actualizar rewards antes de cualquier transferencia
        for (uint256 i = 0; i < ids.length; i++) {
            if (from != address(0)) {
                _updateRewards(ids[i], from);
            }
            if (to != address(0)) {
                _updateRewards(ids[i], to);
            }
        }
        // Llamar al método padre para ejecutar la transferencia real
        super._update(from, to, ids, values);
    }

    /**
     * @notice Verifica si el contrato soporta una interfaz específica
     * @dev Implementa ERC-165 para detección de interfaces
     * @param interfaceId ID de la interfaz a verificar
     * @return true si la interfaz es soportada
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Permite al contrato recibir ETH directamente
     * @dev ETH enviado directamente queda como dust (recuperable con rescueDust)
     */
    receive() external payable {}
}
