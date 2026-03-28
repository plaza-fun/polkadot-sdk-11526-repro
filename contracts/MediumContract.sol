// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MediumContract - Over-24KB EVM limit, under PVM 100KB limit (~25-30KB deployed bytecode)
/// @notice Generic data-management platform with 10 CRUD domains.
///         On EVM this exceeds EIP-170's 24KB limit and cannot be deployed.
///         On PVM (PolkaVM) the limit is 100KB, so this should deploy successfully.
///         If deployment fails on Passet Hub with BlobTooLarge, that confirms issue #11526.
contract MediumContract {
    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    enum OrderStatus    { Pending, Confirmed, Shipped, Delivered, Cancelled }
    enum PaymentStatus  { Unpaid, Paid, Refunded, Disputed }
    enum ShipmentStatus { Preparing, InTransit, Delivered, Returned }
    enum RefundStatus   { Requested, Approved, Rejected, Processed }

    // -------------------------------------------------------------------------
    // Structs  (10 domains)
    // -------------------------------------------------------------------------

    struct User {
        uint256 id;
        address wallet;
        string  username;
        string  email;
        bytes32 passwordHash;
        bool    active;
        uint256 role;       // 0=user, 1=admin, 2=moderator
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Product {
        uint256 id;
        uint256 categoryId;
        string  name;
        string  description;
        uint256 priceCents;
        uint256 stock;
        bool    available;
        bytes32 sku;
        address seller;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Category {
        uint256 id;
        uint256 parentId;
        string  name;
        string  slug;
        bool    active;
        uint256 sortOrder;
        uint256 createdAt;
    }

    struct Order {
        uint256       id;
        uint256       userId;
        uint256       totalCents;
        OrderStatus   status;
        bytes32       trackingRef;
        string        shippingAddress;
        uint256       createdAt;
        uint256       updatedAt;
    }

    struct Review {
        uint256 id;
        uint256 productId;
        uint256 userId;
        uint8   rating;     // 1-5
        string  title;
        string  body;
        bool    verified;
        uint256 helpfulVotes;
        uint256 createdAt;
    }

    struct Inventory {
        uint256 id;
        uint256 productId;
        int256  delta;       // positive=restock, negative=sale
        string  reason;
        address updatedBy;
        uint256 timestamp;
    }

    struct Shipment {
        uint256       id;
        uint256       orderId;
        string        carrier;
        string        trackingNumber;
        ShipmentStatus status;
        uint256       estimatedDelivery;
        uint256       actualDelivery;
        uint256       createdAt;
    }

    struct Payment {
        uint256       id;
        uint256       orderId;
        uint256       amountCents;
        PaymentStatus status;
        bytes32       txHash;
        address       payer;
        uint256       paidAt;
        uint256       createdAt;
    }

    struct Refund {
        uint256      id;
        uint256      orderId;
        uint256      paymentId;
        uint256      amountCents;
        RefundStatus status;
        string       reason;
        address      requestedBy;
        uint256      createdAt;
        uint256      processedAt;
    }

    struct Audit {
        uint256 id;
        address actor;
        bytes32 action;     // keccak256 of action name
        bytes32 entityType;
        uint256 entityId;
        bytes   data;
        uint256 timestamp;
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(uint256 => User)      private _users;
    mapping(uint256 => Product)   private _products;
    mapping(uint256 => Category)  private _categories;
    mapping(uint256 => Order)     private _orders;
    mapping(uint256 => Review)    private _reviews;
    mapping(uint256 => Inventory) private _inventoryLogs;
    mapping(uint256 => Shipment)  private _shipments;
    mapping(uint256 => Payment)   private _payments;
    mapping(uint256 => Refund)    private _refunds;
    mapping(uint256 => Audit)     private _audits;

    mapping(address => uint256)   private _userByWallet;
    mapping(uint256 => uint256[]) private _ordersByUser;
    mapping(uint256 => uint256[]) private _productsByCategory;
    mapping(uint256 => uint256[]) private _reviewsByProduct;
    mapping(uint256 => uint256[]) private _shipmentsByOrder;
    mapping(uint256 => uint256[]) private _paymentsByOrder;
    mapping(uint256 => uint256[]) private _refundsByOrder;
    mapping(bytes32 => uint256)   private _productBySku;

    uint256 private _nextUserId      = 1;
    uint256 private _nextProductId   = 1;
    uint256 private _nextCategoryId  = 1;
    uint256 private _nextOrderId     = 1;
    uint256 private _nextReviewId    = 1;
    uint256 private _nextInventoryId = 1;
    uint256 private _nextShipmentId  = 1;
    uint256 private _nextPaymentId   = 1;
    uint256 private _nextRefundId    = 1;
    uint256 private _nextAuditId     = 1;

    address public owner;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event UserCreated(uint256 indexed id, address indexed wallet);
    event UserUpdated(uint256 indexed id);
    event UserDeactivated(uint256 indexed id);

    event ProductCreated(uint256 indexed id, uint256 indexed categoryId, bytes32 sku);
    event ProductUpdated(uint256 indexed id);
    event ProductDeleted(uint256 indexed id);

    event CategoryCreated(uint256 indexed id, string name);
    event CategoryUpdated(uint256 indexed id);
    event CategoryDeleted(uint256 indexed id);

    event OrderCreated(uint256 indexed id, uint256 indexed userId, uint256 totalCents);
    event OrderUpdated(uint256 indexed id, OrderStatus status);
    event OrderCancelled(uint256 indexed id);

    event ReviewCreated(uint256 indexed id, uint256 indexed productId, uint256 indexed userId);
    event ReviewUpdated(uint256 indexed id);
    event ReviewDeleted(uint256 indexed id);

    event InventoryLogged(uint256 indexed id, uint256 indexed productId, int256 delta);

    event ShipmentCreated(uint256 indexed id, uint256 indexed orderId);
    event ShipmentUpdated(uint256 indexed id, ShipmentStatus status);

    event PaymentCreated(uint256 indexed id, uint256 indexed orderId, uint256 amountCents);
    event PaymentStatusUpdated(uint256 indexed id, PaymentStatus status);

    event RefundRequested(uint256 indexed id, uint256 indexed orderId);
    event RefundProcessed(uint256 indexed id, RefundStatus status);

    event AuditLogged(uint256 indexed id, address indexed actor, bytes32 action);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "MediumContract: not owner");
        _;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _logAudit(bytes32 action, bytes32 entityType, uint256 entityId, bytes memory data) internal {
        uint256 id = _nextAuditId++;
        _audits[id] = Audit({
            id: id,
            actor: msg.sender,
            action: action,
            entityType: entityType,
            entityId: entityId,
            data: data,
            timestamp: block.timestamp
        });
        emit AuditLogged(id, msg.sender, action);
    }

    function _requireNonEmpty(string calldata s, string memory field) internal pure {
        require(bytes(s).length > 0, string(abi.encodePacked("MediumContract: empty ", field)));
    }

    function _requirePositive(uint256 v, string memory field) internal pure {
        require(v > 0, string(abi.encodePacked("MediumContract: zero ", field)));
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // =========================================================================
    // USER DOMAIN
    // =========================================================================

    function createUser(
        address wallet,
        string calldata username,
        string calldata email,
        bytes32 passwordHash,
        uint256 role
    ) external returns (uint256 id) {
        require(wallet != address(0), "MediumContract: zero address");
        require(_userByWallet[wallet] == 0, "MediumContract: wallet exists");
        _requireNonEmpty(username, "username");
        require(role <= 2, "MediumContract: invalid role");

        id = _nextUserId++;
        _users[id] = User({
            id: id,
            wallet: wallet,
            username: username,
            email: email,
            passwordHash: passwordHash,
            active: true,
            role: role,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        _userByWallet[wallet] = id;
        _logAudit(keccak256("USER_CREATE"), keccak256("User"), id, abi.encode(wallet, username));
        emit UserCreated(id, wallet);
    }

    function updateUser(uint256 id, string calldata username, string calldata email, uint256 role) external {
        require(_users[id].id != 0, "MediumContract: user not found");
        _requireNonEmpty(username, "username");
        require(role <= 2, "MediumContract: invalid role");
        User storage u = _users[id];
        u.username = username;
        u.email = email;
        u.role = role;
        u.updatedAt = block.timestamp;
        _logAudit(keccak256("USER_UPDATE"), keccak256("User"), id, abi.encode(username, role));
        emit UserUpdated(id);
    }

    function deactivateUser(uint256 id) external onlyOwner {
        require(_users[id].id != 0, "MediumContract: user not found");
        _users[id].active = false;
        _users[id].updatedAt = block.timestamp;
        _logAudit(keccak256("USER_DELETE"), keccak256("User"), id, "");
        emit UserDeactivated(id);
    }

    function batchCreateUsers(
        address[] calldata wallets,
        string[] calldata usernames,
        bytes32[] calldata passwordHashes
    ) external returns (uint256[] memory ids) {
        uint256 n = wallets.length;
        require(n == usernames.length && n == passwordHashes.length, "MediumContract: length mismatch");
        require(n <= 50, "MediumContract: batch too large");
        ids = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            require(wallets[i] != address(0), "MediumContract: zero address in batch");
            require(_userByWallet[wallets[i]] == 0, "MediumContract: duplicate wallet");
            uint256 uid = _nextUserId++;
            _users[uid] = User({
                id: uid,
                wallet: wallets[i],
                username: usernames[i],
                email: "",
                passwordHash: passwordHashes[i],
                active: true,
                role: 0,
                createdAt: block.timestamp,
                updatedAt: block.timestamp
            });
            _userByWallet[wallets[i]] = uid;
            ids[i] = uid;
            emit UserCreated(uid, wallets[i]);
        }
    }

    function getUser(uint256 id) external view returns (User memory) {
        require(_users[id].id != 0, "MediumContract: user not found");
        return _users[id];
    }

    function getUserByWallet(address wallet) external view returns (User memory) {
        uint256 id = _userByWallet[wallet];
        require(id != 0, "MediumContract: not found");
        return _users[id];
    }

    // =========================================================================
    // PRODUCT DOMAIN
    // =========================================================================

    function createProduct(
        uint256 categoryId,
        string calldata name,
        string calldata description,
        uint256 priceCents,
        uint256 stock,
        bytes32 sku
    ) external returns (uint256 id) {
        require(_categories[categoryId].id != 0, "MediumContract: category not found");
        _requireNonEmpty(name, "name");
        _requirePositive(priceCents, "price");
        require(_productBySku[sku] == 0, "MediumContract: SKU exists");

        id = _nextProductId++;
        _products[id] = Product({
            id: id,
            categoryId: categoryId,
            name: name,
            description: description,
            priceCents: priceCents,
            stock: stock,
            available: true,
            sku: sku,
            seller: msg.sender,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        _productsByCategory[categoryId].push(id);
        _productBySku[sku] = id;
        _logAudit(keccak256("PRODUCT_CREATE"), keccak256("Product"), id, abi.encode(sku, priceCents));
        emit ProductCreated(id, categoryId, sku);
    }

    function updateProduct(uint256 id, string calldata name, uint256 priceCents, bool available) external {
        require(_products[id].id != 0, "MediumContract: product not found");
        _requireNonEmpty(name, "name");
        _requirePositive(priceCents, "price");
        Product storage p = _products[id];
        p.name = name;
        p.priceCents = priceCents;
        p.available = available;
        p.updatedAt = block.timestamp;
        _logAudit(keccak256("PRODUCT_UPDATE"), keccak256("Product"), id, abi.encode(name, priceCents));
        emit ProductUpdated(id);
    }

    function deleteProduct(uint256 id) external onlyOwner {
        require(_products[id].id != 0, "MediumContract: product not found");
        delete _productBySku[_products[id].sku];
        delete _products[id];
        _logAudit(keccak256("PRODUCT_DELETE"), keccak256("Product"), id, "");
        emit ProductDeleted(id);
    }

    function batchUpdateStock(uint256[] calldata ids, uint256[] calldata stocks) external {
        require(ids.length == stocks.length, "MediumContract: length mismatch");
        for (uint256 i = 0; i < ids.length; i++) {
            require(_products[ids[i]].id != 0, "MediumContract: product not found");
            _products[ids[i]].stock = stocks[i];
            _products[ids[i]].updatedAt = block.timestamp;
        }
    }

    function getProduct(uint256 id) external view returns (Product memory) {
        require(_products[id].id != 0, "MediumContract: product not found");
        return _products[id];
    }

    function getProductsByCategory(uint256 categoryId) external view returns (uint256[] memory) {
        return _productsByCategory[categoryId];
    }

    // =========================================================================
    // CATEGORY DOMAIN
    // =========================================================================

    function createCategory(string calldata name, string calldata slug, uint256 parentId, uint256 sortOrder) external returns (uint256 id) {
        _requireNonEmpty(name, "name");
        _requireNonEmpty(slug, "slug");
        id = _nextCategoryId++;
        _categories[id] = Category({
            id: id,
            parentId: parentId,
            name: name,
            slug: slug,
            active: true,
            sortOrder: sortOrder,
            createdAt: block.timestamp
        });
        _logAudit(keccak256("CATEGORY_CREATE"), keccak256("Category"), id, abi.encode(name));
        emit CategoryCreated(id, name);
    }

    function updateCategory(uint256 id, string calldata name, bool active, uint256 sortOrder) external {
        require(_categories[id].id != 0, "MediumContract: category not found");
        _categories[id].name = name;
        _categories[id].active = active;
        _categories[id].sortOrder = sortOrder;
        _logAudit(keccak256("CATEGORY_UPDATE"), keccak256("Category"), id, abi.encode(name));
        emit CategoryUpdated(id);
    }

    function deleteCategory(uint256 id) external onlyOwner {
        require(_categories[id].id != 0, "MediumContract: category not found");
        require(_productsByCategory[id].length == 0, "MediumContract: category has products");
        delete _categories[id];
        _logAudit(keccak256("CATEGORY_DELETE"), keccak256("Category"), id, "");
        emit CategoryDeleted(id);
    }

    function getCategory(uint256 id) external view returns (Category memory) {
        require(_categories[id].id != 0, "MediumContract: category not found");
        return _categories[id];
    }

    // =========================================================================
    // ORDER DOMAIN
    // =========================================================================

    function createOrder(
        uint256 userId,
        uint256 totalCents,
        string calldata shippingAddress
    ) external returns (uint256 id) {
        require(_users[userId].id != 0 && _users[userId].active, "MediumContract: user invalid");
        _requirePositive(totalCents, "total");
        _requireNonEmpty(shippingAddress, "shippingAddress");

        id = _nextOrderId++;
        _orders[id] = Order({
            id: id,
            userId: userId,
            totalCents: totalCents,
            status: OrderStatus.Pending,
            trackingRef: bytes32(0),
            shippingAddress: shippingAddress,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        _ordersByUser[userId].push(id);
        _logAudit(keccak256("ORDER_CREATE"), keccak256("Order"), id, abi.encode(userId, totalCents));
        emit OrderCreated(id, userId, totalCents);
    }

    function updateOrderStatus(uint256 id, OrderStatus status) external {
        require(_orders[id].id != 0, "MediumContract: order not found");
        require(_orders[id].status != OrderStatus.Cancelled, "MediumContract: order cancelled");
        _orders[id].status = status;
        _orders[id].updatedAt = block.timestamp;
        _logAudit(keccak256("ORDER_UPDATE"), keccak256("Order"), id, abi.encode(uint8(status)));
        emit OrderUpdated(id, status);
    }

    function cancelOrder(uint256 id) external {
        require(_orders[id].id != 0, "MediumContract: order not found");
        require(_orders[id].status == OrderStatus.Pending, "MediumContract: not cancellable");
        _orders[id].status = OrderStatus.Cancelled;
        _orders[id].updatedAt = block.timestamp;
        _logAudit(keccak256("ORDER_CANCEL"), keccak256("Order"), id, "");
        emit OrderCancelled(id);
    }

    function getOrder(uint256 id) external view returns (Order memory) {
        require(_orders[id].id != 0, "MediumContract: order not found");
        return _orders[id];
    }

    function getOrdersByUser(uint256 userId) external view returns (uint256[] memory) {
        return _ordersByUser[userId];
    }

    // =========================================================================
    // REVIEW DOMAIN
    // =========================================================================

    function createReview(uint256 productId, uint256 userId, uint8 rating, string calldata title, string calldata body) external returns (uint256 id) {
        require(_products[productId].id != 0, "MediumContract: product not found");
        require(_users[userId].id != 0, "MediumContract: user not found");
        require(rating >= 1 && rating <= 5, "MediumContract: invalid rating");
        _requireNonEmpty(title, "title");

        id = _nextReviewId++;
        _reviews[id] = Review({
            id: id,
            productId: productId,
            userId: userId,
            rating: rating,
            title: title,
            body: body,
            verified: false,
            helpfulVotes: 0,
            createdAt: block.timestamp
        });
        _reviewsByProduct[productId].push(id);
        _logAudit(keccak256("REVIEW_CREATE"), keccak256("Review"), id, abi.encode(productId, userId, rating));
        emit ReviewCreated(id, productId, userId);
    }

    function verifyReview(uint256 id) external onlyOwner {
        require(_reviews[id].id != 0, "MediumContract: review not found");
        _reviews[id].verified = true;
        emit ReviewUpdated(id);
    }

    function voteReviewHelpful(uint256 id) external {
        require(_reviews[id].id != 0, "MediumContract: review not found");
        _reviews[id].helpfulVotes += 1;
    }

    function deleteReview(uint256 id) external onlyOwner {
        require(_reviews[id].id != 0, "MediumContract: review not found");
        delete _reviews[id];
        emit ReviewDeleted(id);
    }

    function getReview(uint256 id) external view returns (Review memory) {
        require(_reviews[id].id != 0, "MediumContract: review not found");
        return _reviews[id];
    }

    function getReviewsByProduct(uint256 productId) external view returns (uint256[] memory) {
        return _reviewsByProduct[productId];
    }

    function getAverageRating(uint256 productId) external view returns (uint256 avg, uint256 count) {
        uint256[] storage ids = _reviewsByProduct[productId];
        count = ids.length;
        if (count == 0) return (0, 0);
        uint256 sum = 0;
        for (uint256 i = 0; i < count; i++) {
            sum += _reviews[ids[i]].rating;
        }
        avg = sum / count;
    }

    // =========================================================================
    // INVENTORY DOMAIN
    // =========================================================================

    function logInventory(uint256 productId, int256 delta, string calldata reason) external returns (uint256 id) {
        require(_products[productId].id != 0, "MediumContract: product not found");
        require(delta != 0, "MediumContract: zero delta");

        if (delta < 0) {
            uint256 decrement = uint256(-delta);
            require(_products[productId].stock >= decrement, "MediumContract: insufficient stock");
            _products[productId].stock -= decrement;
        } else {
            _products[productId].stock += uint256(delta);
        }

        id = _nextInventoryId++;
        _inventoryLogs[id] = Inventory({
            id: id,
            productId: productId,
            delta: delta,
            reason: reason,
            updatedBy: msg.sender,
            timestamp: block.timestamp
        });
        _logAudit(keccak256("INVENTORY_LOG"), keccak256("Inventory"), id, abi.encode(productId, delta));
        emit InventoryLogged(id, productId, delta);
    }

    function getInventoryLog(uint256 id) external view returns (Inventory memory) {
        require(_inventoryLogs[id].id != 0, "MediumContract: log not found");
        return _inventoryLogs[id];
    }

    // =========================================================================
    // SHIPMENT DOMAIN
    // =========================================================================

    function createShipment(uint256 orderId, string calldata carrier, string calldata trackingNumber, uint256 estimatedDelivery) external returns (uint256 id) {
        require(_orders[orderId].id != 0, "MediumContract: order not found");
        _requireNonEmpty(carrier, "carrier");
        _requireNonEmpty(trackingNumber, "trackingNumber");

        id = _nextShipmentId++;
        _shipments[id] = Shipment({
            id: id,
            orderId: orderId,
            carrier: carrier,
            trackingNumber: trackingNumber,
            status: ShipmentStatus.Preparing,
            estimatedDelivery: estimatedDelivery,
            actualDelivery: 0,
            createdAt: block.timestamp
        });
        _shipmentsByOrder[orderId].push(id);
        _logAudit(keccak256("SHIPMENT_CREATE"), keccak256("Shipment"), id, abi.encode(orderId, carrier));
        emit ShipmentCreated(id, orderId);
    }

    function updateShipment(uint256 id, ShipmentStatus status, uint256 actualDelivery) external {
        require(_shipments[id].id != 0, "MediumContract: shipment not found");
        _shipments[id].status = status;
        if (status == ShipmentStatus.Delivered) {
            _shipments[id].actualDelivery = actualDelivery > 0 ? actualDelivery : block.timestamp;
        }
        _logAudit(keccak256("SHIPMENT_UPDATE"), keccak256("Shipment"), id, abi.encode(uint8(status)));
        emit ShipmentUpdated(id, status);
    }

    function getShipment(uint256 id) external view returns (Shipment memory) {
        require(_shipments[id].id != 0, "MediumContract: shipment not found");
        return _shipments[id];
    }

    // =========================================================================
    // PAYMENT DOMAIN
    // =========================================================================

    function createPayment(uint256 orderId, uint256 amountCents, bytes32 txHash) external returns (uint256 id) {
        require(_orders[orderId].id != 0, "MediumContract: order not found");
        _requirePositive(amountCents, "amount");

        id = _nextPaymentId++;
        _payments[id] = Payment({
            id: id,
            orderId: orderId,
            amountCents: amountCents,
            status: PaymentStatus.Unpaid,
            txHash: txHash,
            payer: msg.sender,
            paidAt: 0,
            createdAt: block.timestamp
        });
        _paymentsByOrder[orderId].push(id);
        _logAudit(keccak256("PAYMENT_CREATE"), keccak256("Payment"), id, abi.encode(orderId, amountCents));
        emit PaymentCreated(id, orderId, amountCents);
    }

    function confirmPayment(uint256 id) external {
        require(_payments[id].id != 0, "MediumContract: payment not found");
        require(_payments[id].status == PaymentStatus.Unpaid, "MediumContract: not unpaid");
        _payments[id].status = PaymentStatus.Paid;
        _payments[id].paidAt = block.timestamp;
        _logAudit(keccak256("PAYMENT_CONFIRM"), keccak256("Payment"), id, "");
        emit PaymentStatusUpdated(id, PaymentStatus.Paid);
    }

    function getPayment(uint256 id) external view returns (Payment memory) {
        require(_payments[id].id != 0, "MediumContract: payment not found");
        return _payments[id];
    }

    // =========================================================================
    // REFUND DOMAIN
    // =========================================================================

    function requestRefund(uint256 orderId, uint256 paymentId, uint256 amountCents, string calldata reason) external returns (uint256 id) {
        require(_orders[orderId].id != 0, "MediumContract: order not found");
        require(_payments[paymentId].id != 0, "MediumContract: payment not found");
        require(_payments[paymentId].status == PaymentStatus.Paid, "MediumContract: payment not paid");
        _requirePositive(amountCents, "amount");
        require(amountCents <= _payments[paymentId].amountCents, "MediumContract: refund exceeds payment");

        id = _nextRefundId++;
        _refunds[id] = Refund({
            id: id,
            orderId: orderId,
            paymentId: paymentId,
            amountCents: amountCents,
            status: RefundStatus.Requested,
            reason: reason,
            requestedBy: msg.sender,
            createdAt: block.timestamp,
            processedAt: 0
        });
        _refundsByOrder[orderId].push(id);
        _logAudit(keccak256("REFUND_REQUEST"), keccak256("Refund"), id, abi.encode(orderId, amountCents));
        emit RefundRequested(id, orderId);
    }

    function processRefund(uint256 id, RefundStatus status) external onlyOwner {
        require(_refunds[id].id != 0, "MediumContract: refund not found");
        require(_refunds[id].status == RefundStatus.Requested, "MediumContract: already processed");
        require(status == RefundStatus.Approved || status == RefundStatus.Rejected || status == RefundStatus.Processed, "MediumContract: invalid status");
        _refunds[id].status = status;
        _refunds[id].processedAt = block.timestamp;
        _logAudit(keccak256("REFUND_PROCESS"), keccak256("Refund"), id, abi.encode(uint8(status)));
        emit RefundProcessed(id, status);
    }

    function getRefund(uint256 id) external view returns (Refund memory) {
        require(_refunds[id].id != 0, "MediumContract: refund not found");
        return _refunds[id];
    }

    // =========================================================================
    // AUDIT DOMAIN  (read-only queries)
    // =========================================================================

    function getAudit(uint256 id) external view returns (Audit memory) {
        require(_audits[id].id != 0, "MediumContract: audit not found");
        return _audits[id];
    }

    function auditCount() external view returns (uint256) {
        return _nextAuditId - 1;
    }

    // =========================================================================
    // AGGREGATE QUERIES
    // =========================================================================

    function userCount() external view returns (uint256) { return _nextUserId - 1; }
    function productCount() external view returns (uint256) { return _nextProductId - 1; }
    function orderCount() external view returns (uint256) { return _nextOrderId - 1; }
    function reviewCount() external view returns (uint256) { return _nextReviewId - 1; }

    function getOrderSummary(uint256 orderId) external view returns (
        Order memory order,
        uint256 paymentCount,
        uint256 shipmentCount,
        uint256 refundCount
    ) {
        require(_orders[orderId].id != 0, "MediumContract: order not found");
        order = _orders[orderId];
        paymentCount = _paymentsByOrder[orderId].length;
        shipmentCount = _shipmentsByOrder[orderId].length;
        refundCount = _refundsByOrder[orderId].length;
    }

    function getTotalRevenue(uint256[] calldata orderIds) external view returns (uint256 total) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (_orders[orderIds[i]].id != 0 && _orders[orderIds[i]].status == OrderStatus.Delivered) {
                total += _orders[orderIds[i]].totalCents;
            }
        }
    }
}
