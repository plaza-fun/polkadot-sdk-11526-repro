// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title LargeContract - ~45-50KB deployed bytecode
/// @notice Enterprise-grade data platform with 15+ CRUD domains, complex queries,
///         batch operations, access control, and aggregate calculations.
///         Targets ~45-50KB to remain well under the PVM 100KB limit
///         while far exceeding the EVM 24KB limit.
contract LargeContract {
    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    enum OrderStatus    { Pending, Confirmed, Processing, Shipped, Delivered, Cancelled, Refunded }
    enum PaymentStatus  { Unpaid, Authorised, Captured, Refunded, Disputed, Voided }
    enum ShipmentStatus { Created, PickedUp, InTransit, OutForDelivery, Delivered, Failed, Returned }
    enum RefundStatus   { Requested, UnderReview, Approved, Rejected, Processed }
    enum TicketStatus   { Open, InProgress, Resolved, Closed, Escalated }
    enum TicketPriority { Low, Medium, High, Critical }
    enum CouponType     { Percentage, FixedAmount, FreeShipping }
    enum SubscriptionStatus { Active, Paused, Cancelled, Expired }

    // -------------------------------------------------------------------------
    // Roles (bitmask)
    // -------------------------------------------------------------------------

    uint256 constant ROLE_ADMIN      = 1;
    uint256 constant ROLE_MANAGER    = 2;
    uint256 constant ROLE_STAFF      = 4;
    uint256 constant ROLE_FINANCE    = 8;
    uint256 constant ROLE_LOGISTICS  = 16;

    // -------------------------------------------------------------------------
    // Structs (15 domains)
    // -------------------------------------------------------------------------

    struct User {
        uint256 id;
        address wallet;
        string  username;
        string  email;
        bytes32 passwordHash;
        uint256 roles;
        bool    active;
        uint256 loyaltyPoints;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Organisation {
        uint256 id;
        string  name;
        string  taxId;
        address billingWallet;
        bool    verified;
        uint256 creditLimit;
        uint256 createdAt;
    }

    struct Product {
        uint256 id;
        uint256 categoryId;
        string  name;
        string  description;
        uint256 priceCents;
        uint256 stock;
        uint256 reservedStock;
        bool    available;
        bytes32 sku;
        bytes32 barcode;
        address seller;
        uint256 weightGrams;
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
        uint256 productCount;
        uint256 createdAt;
    }

    struct Order {
        uint256      id;
        uint256      userId;
        uint256      orgId;
        uint256      totalCents;
        uint256      discountCents;
        uint256      taxCents;
        uint256      shippingCents;
        OrderStatus  status;
        bytes32      couponCode;
        string       shippingAddress;
        string       billingAddress;
        uint256      createdAt;
        uint256      updatedAt;
    }

    struct OrderLine {
        uint256 id;
        uint256 orderId;
        uint256 productId;
        uint256 qty;
        uint256 unitPriceCents;
        uint256 discountCents;
        uint256 taxCents;
    }

    struct Review {
        uint256 id;
        uint256 productId;
        uint256 userId;
        uint8   rating;
        string  title;
        string  body;
        bool    verified;
        bool    flagged;
        uint256 helpfulVotes;
        uint256 unhelpfulVotes;
        uint256 createdAt;
    }

    struct Inventory {
        uint256 id;
        uint256 productId;
        int256  delta;
        uint256 newStock;
        string  reason;
        bytes32 externalRef;
        address updatedBy;
        uint256 timestamp;
    }

    struct Shipment {
        uint256        id;
        uint256        orderId;
        string         carrier;
        string         trackingNumber;
        ShipmentStatus status;
        uint256        weightGrams;
        uint256        estimatedDelivery;
        uint256        actualDelivery;
        string         notes;
        uint256        createdAt;
    }

    struct Payment {
        uint256       id;
        uint256       orderId;
        uint256       userId;
        uint256       amountCents;
        PaymentStatus status;
        bytes32       txHash;
        bytes32       gatewayRef;
        address       payer;
        string        method;   // "crypto", "card", "bank"
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
        address      processedBy;
        uint256      createdAt;
        uint256      processedAt;
    }

    struct Coupon {
        uint256    id;
        bytes32    code;
        CouponType couponType;
        uint256    value;          // pct (0-10000 bps) or fixed cents
        uint256    minOrderCents;
        uint256    maxUsages;
        uint256    usageCount;
        uint256    expiresAt;
        bool       active;
        uint256    createdAt;
    }

    struct Subscription {
        uint256            id;
        uint256            userId;
        uint256            planId;
        SubscriptionStatus status;
        uint256            periodStart;
        uint256            periodEnd;
        uint256            amountCents;
        uint256            renewalCount;
        uint256            createdAt;
        uint256            updatedAt;
    }

    struct SupportTicket {
        uint256         id;
        uint256         userId;
        uint256         orderId;    // 0 if not order-related
        TicketPriority  priority;
        TicketStatus    status;
        string          subject;
        string          body;
        address         assignedTo;
        uint256         resolvedAt;
        uint256         createdAt;
        uint256         updatedAt;
    }

    struct Audit {
        uint256 id;
        address actor;
        bytes32 action;
        bytes32 entityType;
        uint256 entityId;
        bytes   data;
        uint256 timestamp;
    }

    struct Notification {
        uint256 id;
        uint256 userId;
        string  channel;   // "email", "sms", "push"
        string  subject;
        string  body;
        bool    sent;
        bool    read;
        uint256 sentAt;
        uint256 createdAt;
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(uint256 => User)          private _users;
    mapping(uint256 => Organisation)  private _orgs;
    mapping(uint256 => Product)       private _products;
    mapping(uint256 => Category)      private _categories;
    mapping(uint256 => Order)         private _orders;
    mapping(uint256 => OrderLine)     private _lines;
    mapping(uint256 => Review)        private _reviews;
    mapping(uint256 => Inventory)     private _inventory;
    mapping(uint256 => Shipment)      private _shipments;
    mapping(uint256 => Payment)       private _payments;
    mapping(uint256 => Refund)        private _refunds;
    mapping(uint256 => Coupon)        private _coupons;
    mapping(uint256 => Subscription)  private _subscriptions;
    mapping(uint256 => SupportTicket) private _tickets;
    mapping(uint256 => Audit)         private _audits;
    mapping(uint256 => Notification)  private _notifications;

    // Index mappings
    mapping(address => uint256)   private _userByWallet;
    mapping(bytes32 => uint256)   private _productBySku;
    mapping(bytes32 => uint256)   private _couponByCode;
    mapping(uint256 => uint256[]) private _ordersByUser;
    mapping(uint256 => uint256[]) private _linesByOrder;
    mapping(uint256 => uint256[]) private _productsByCategory;
    mapping(uint256 => uint256[]) private _reviewsByProduct;
    mapping(uint256 => uint256[]) private _shipmentsByOrder;
    mapping(uint256 => uint256[]) private _paymentsByOrder;
    mapping(uint256 => uint256[]) private _refundsByOrder;
    mapping(uint256 => uint256[]) private _ticketsByUser;
    mapping(uint256 => uint256[]) private _subscriptionsByUser;
    mapping(uint256 => uint256[]) private _notificationsByUser;

    // Counters
    uint256 private _nextUserId       = 1;
    uint256 private _nextOrgId        = 1;
    uint256 private _nextProductId    = 1;
    uint256 private _nextCategoryId   = 1;
    uint256 private _nextOrderId      = 1;
    uint256 private _nextLineId       = 1;
    uint256 private _nextReviewId     = 1;
    uint256 private _nextInventoryId  = 1;
    uint256 private _nextShipmentId   = 1;
    uint256 private _nextPaymentId    = 1;
    uint256 private _nextRefundId     = 1;
    uint256 private _nextCouponId     = 1;
    uint256 private _nextSubId        = 1;
    uint256 private _nextTicketId     = 1;
    uint256 private _nextAuditId      = 1;
    uint256 private _nextNotifId      = 1;

    address public owner;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event UserCreated(uint256 indexed id, address indexed wallet);
    event UserUpdated(uint256 indexed id);
    event UserRoleChanged(uint256 indexed id, uint256 roles);

    event OrgCreated(uint256 indexed id, string name);
    event OrgUpdated(uint256 indexed id);

    event ProductCreated(uint256 indexed id, bytes32 sku);
    event ProductUpdated(uint256 indexed id);
    event ProductDeleted(uint256 indexed id);

    event CategoryCreated(uint256 indexed id);
    event CategoryUpdated(uint256 indexed id);

    event OrderCreated(uint256 indexed id, uint256 indexed userId, uint256 totalCents);
    event OrderUpdated(uint256 indexed id, OrderStatus status);
    event OrderLineAdded(uint256 indexed orderId, uint256 indexed lineId);

    event ReviewCreated(uint256 indexed id, uint256 indexed productId);
    event ReviewFlagged(uint256 indexed id);
    event ReviewDeleted(uint256 indexed id);

    event InventoryLogged(uint256 indexed id, uint256 indexed productId, int256 delta);

    event ShipmentCreated(uint256 indexed id, uint256 indexed orderId);
    event ShipmentUpdated(uint256 indexed id, ShipmentStatus status);

    event PaymentCreated(uint256 indexed id, uint256 indexed orderId);
    event PaymentUpdated(uint256 indexed id, PaymentStatus status);

    event RefundRequested(uint256 indexed id, uint256 indexed orderId);
    event RefundProcessed(uint256 indexed id, RefundStatus status);

    event CouponCreated(uint256 indexed id, bytes32 code);
    event CouponUsed(bytes32 indexed code, uint256 indexed orderId);
    event CouponDeactivated(uint256 indexed id);

    event SubscriptionCreated(uint256 indexed id, uint256 indexed userId);
    event SubscriptionRenewed(uint256 indexed id);
    event SubscriptionCancelled(uint256 indexed id);

    event TicketCreated(uint256 indexed id, uint256 indexed userId);
    event TicketUpdated(uint256 indexed id, TicketStatus status);
    event TicketAssigned(uint256 indexed id, address assignedTo);

    event NotificationCreated(uint256 indexed id, uint256 indexed userId);
    event NotificationSent(uint256 indexed id);

    event AuditLogged(uint256 indexed id, address indexed actor, bytes32 action);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "LC: not owner");
        _;
    }

    modifier hasRole(uint256 role) {
        uint256 uid = _userByWallet[msg.sender];
        require(uid != 0 && (_users[uid].roles & role) != 0, "LC: missing role");
        _;
    }

    modifier userExists(uint256 id) {
        require(_users[id].id != 0, "LC: user not found");
        _;
    }

    modifier productExists(uint256 id) {
        require(_products[id].id != 0, "LC: product not found");
        _;
    }

    modifier orderExists(uint256 id) {
        require(_orders[id].id != 0, "LC: order not found");
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _audit(bytes32 action, bytes32 etype, uint256 eid, bytes memory data) internal {
        uint256 id = _nextAuditId++;
        _audits[id] = Audit({ id: id, actor: msg.sender, action: action, entityType: etype, entityId: eid, data: data, timestamp: block.timestamp });
        emit AuditLogged(id, msg.sender, action);
    }

    function _ne(string calldata s, string memory f) internal pure {
        require(bytes(s).length > 0, string(abi.encodePacked("LC: empty ", f)));
    }

    function _pos(uint256 v, string memory f) internal pure {
        require(v > 0, string(abi.encodePacked("LC: zero ", f)));
    }

    function _applyDiscount(uint256 amountCents, uint256 couponId) internal returns (uint256 discountCents) {
        if (couponId == 0) return 0;
        Coupon storage c = _coupons[couponId];
        require(c.id != 0 && c.active, "LC: coupon invalid");
        require(block.timestamp < c.expiresAt, "LC: coupon expired");
        require(c.maxUsages == 0 || c.usageCount < c.maxUsages, "LC: coupon exhausted");
        require(amountCents >= c.minOrderCents, "LC: order below minimum");

        if (c.couponType == CouponType.Percentage) {
            discountCents = (amountCents * c.value) / 10000;
        } else if (c.couponType == CouponType.FixedAmount) {
            discountCents = c.value < amountCents ? c.value : amountCents;
        } else {
            discountCents = 0; // FreeShipping handled separately
        }
        c.usageCount++;
    }

    function _calculateTax(uint256 amountCents, uint256 taxBps) internal pure returns (uint256) {
        return (amountCents * taxBps) / 10000;
    }

    function _grantLoyaltyPoints(uint256 userId, uint256 amountCents) internal {
        // 1 point per dollar (100 cents)
        uint256 points = amountCents / 100;
        if (points > 0) {
            _users[userId].loyaltyPoints += points;
        }
    }

    function _createNotification(uint256 userId, string memory channel, string memory subject, string memory body) internal returns (uint256 id) {
        id = _nextNotifId++;
        _notifications[id] = Notification({
            id: id,
            userId: userId,
            channel: channel,
            subject: subject,
            body: body,
            sent: false,
            read: false,
            sentAt: 0,
            createdAt: block.timestamp
        });
        _notificationsByUser[userId].push(id);
        emit NotificationCreated(id, userId);
    }

    // =========================================================================
    // USER DOMAIN
    // =========================================================================

    function createUser(address wallet, string calldata username, string calldata email, bytes32 pwHash) external returns (uint256 id) {
        require(wallet != address(0), "LC: zero address");
        require(_userByWallet[wallet] == 0, "LC: wallet exists");
        _ne(username, "username");

        id = _nextUserId++;
        _users[id] = User({ id: id, wallet: wallet, username: username, email: email, passwordHash: pwHash, roles: 0, active: true, loyaltyPoints: 0, createdAt: block.timestamp, updatedAt: block.timestamp });
        _userByWallet[wallet] = id;
        _audit(keccak256("USER_CREATE"), keccak256("User"), id, abi.encode(wallet, username));
        emit UserCreated(id, wallet);
    }

    function updateUser(uint256 id, string calldata username, string calldata email) external userExists(id) {
        _ne(username, "username");
        _users[id].username = username;
        _users[id].email = email;
        _users[id].updatedAt = block.timestamp;
        _audit(keccak256("USER_UPDATE"), keccak256("User"), id, abi.encode(username));
        emit UserUpdated(id);
    }

    function setUserRoles(uint256 id, uint256 roles) external onlyOwner userExists(id) {
        _users[id].roles = roles;
        _users[id].updatedAt = block.timestamp;
        _audit(keccak256("USER_ROLES"), keccak256("User"), id, abi.encode(roles));
        emit UserRoleChanged(id, roles);
    }

    function deactivateUser(uint256 id) external onlyOwner userExists(id) {
        _users[id].active = false;
        _users[id].updatedAt = block.timestamp;
        _audit(keccak256("USER_DEACTIVATE"), keccak256("User"), id, "");
    }

    function batchCreateUsers(address[] calldata wallets, string[] calldata usernames, bytes32[] calldata pwHashes) external returns (uint256[] memory ids) {
        uint256 n = wallets.length;
        require(n == usernames.length && n == pwHashes.length && n <= 50, "LC: bad batch");
        ids = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            require(wallets[i] != address(0) && _userByWallet[wallets[i]] == 0, "LC: bad wallet");
            uint256 uid = _nextUserId++;
            _users[uid] = User({ id: uid, wallet: wallets[i], username: usernames[i], email: "", passwordHash: pwHashes[i], roles: 0, active: true, loyaltyPoints: 0, createdAt: block.timestamp, updatedAt: block.timestamp });
            _userByWallet[wallets[i]] = uid;
            ids[i] = uid;
            emit UserCreated(uid, wallets[i]);
        }
    }

    function getUser(uint256 id) external view userExists(id) returns (User memory) { return _users[id]; }
    function getUserByWallet(address w) external view returns (User memory) { uint256 id = _userByWallet[w]; require(id != 0, "LC: not found"); return _users[id]; }
    function userCount() external view returns (uint256) { return _nextUserId - 1; }

    // =========================================================================
    // ORGANISATION DOMAIN
    // =========================================================================

    function createOrg(string calldata name, string calldata taxId, address billingWallet, uint256 creditLimit) external returns (uint256 id) {
        _ne(name, "name");
        id = _nextOrgId++;
        _orgs[id] = Organisation({ id: id, name: name, taxId: taxId, billingWallet: billingWallet, verified: false, creditLimit: creditLimit, createdAt: block.timestamp });
        _audit(keccak256("ORG_CREATE"), keccak256("Org"), id, abi.encode(name));
        emit OrgCreated(id, name);
    }

    function verifyOrg(uint256 id) external onlyOwner {
        require(_orgs[id].id != 0, "LC: org not found");
        _orgs[id].verified = true;
        emit OrgUpdated(id);
    }

    function updateOrgCredit(uint256 id, uint256 creditLimit) external onlyOwner {
        require(_orgs[id].id != 0, "LC: org not found");
        _orgs[id].creditLimit = creditLimit;
        emit OrgUpdated(id);
    }

    function getOrg(uint256 id) external view returns (Organisation memory) { require(_orgs[id].id != 0, "LC: not found"); return _orgs[id]; }

    // =========================================================================
    // CATEGORY DOMAIN
    // =========================================================================

    function createCategory(string calldata name, string calldata slug, uint256 parentId, uint256 sortOrder) external returns (uint256 id) {
        _ne(name, "name");
        id = _nextCategoryId++;
        _categories[id] = Category({ id: id, parentId: parentId, name: name, slug: slug, active: true, sortOrder: sortOrder, productCount: 0, createdAt: block.timestamp });
        _audit(keccak256("CAT_CREATE"), keccak256("Category"), id, abi.encode(name));
        emit CategoryCreated(id);
    }

    function updateCategory(uint256 id, string calldata name, bool active, uint256 sortOrder) external {
        require(_categories[id].id != 0, "LC: cat not found");
        _categories[id].name = name;
        _categories[id].active = active;
        _categories[id].sortOrder = sortOrder;
        emit CategoryUpdated(id);
    }

    function getCategory(uint256 id) external view returns (Category memory) { require(_categories[id].id != 0, "LC: not found"); return _categories[id]; }

    // =========================================================================
    // PRODUCT DOMAIN
    // =========================================================================

    function createProduct(uint256 categoryId, string calldata name, string calldata description, uint256 priceCents, uint256 stock, bytes32 sku, bytes32 barcode, uint256 weightGrams) external returns (uint256 id) {
        require(_categories[categoryId].id != 0, "LC: category not found");
        _ne(name, "name");
        _pos(priceCents, "price");
        require(_productBySku[sku] == 0, "LC: SKU exists");

        id = _nextProductId++;
        _products[id] = Product({ id: id, categoryId: categoryId, name: name, description: description, priceCents: priceCents, stock: stock, reservedStock: 0, available: true, sku: sku, barcode: barcode, seller: msg.sender, weightGrams: weightGrams, createdAt: block.timestamp, updatedAt: block.timestamp });
        _productsByCategory[categoryId].push(id);
        _productBySku[sku] = id;
        _categories[categoryId].productCount++;
        _audit(keccak256("PROD_CREATE"), keccak256("Product"), id, abi.encode(sku, priceCents));
        emit ProductCreated(id, sku);
    }

    function updateProduct(uint256 id, string calldata name, uint256 priceCents, bool available) external productExists(id) {
        _ne(name, "name");
        _pos(priceCents, "price");
        _products[id].name = name;
        _products[id].priceCents = priceCents;
        _products[id].available = available;
        _products[id].updatedAt = block.timestamp;
        _audit(keccak256("PROD_UPDATE"), keccak256("Product"), id, abi.encode(name, priceCents));
        emit ProductUpdated(id);
    }

    function deleteProduct(uint256 id) external onlyOwner productExists(id) {
        uint256 catId = _products[id].categoryId;
        if (_categories[catId].productCount > 0) _categories[catId].productCount--;
        delete _productBySku[_products[id].sku];
        delete _products[id];
        _audit(keccak256("PROD_DELETE"), keccak256("Product"), id, "");
        emit ProductDeleted(id);
    }

    function batchUpdateStock(uint256[] calldata ids, uint256[] calldata stocks) external {
        require(ids.length == stocks.length && ids.length <= 100, "LC: bad batch");
        for (uint256 i = 0; i < ids.length; i++) {
            require(_products[ids[i]].id != 0, "LC: product not found");
            _products[ids[i]].stock = stocks[i];
            _products[ids[i]].updatedAt = block.timestamp;
        }
    }

    function reserveStock(uint256 productId, uint256 qty) external productExists(productId) {
        require(_products[productId].stock >= _products[productId].reservedStock + qty, "LC: insufficient stock");
        _products[productId].reservedStock += qty;
    }

    function releaseStock(uint256 productId, uint256 qty) external productExists(productId) {
        uint256 reserved = _products[productId].reservedStock;
        _products[productId].reservedStock = reserved >= qty ? reserved - qty : 0;
    }

    function getProduct(uint256 id) external view productExists(id) returns (Product memory) { return _products[id]; }
    function getProductBySku(bytes32 sku) external view returns (Product memory) { uint256 id = _productBySku[sku]; require(id != 0, "LC: not found"); return _products[id]; }
    function getProductsByCategory(uint256 catId) external view returns (uint256[] memory) { return _productsByCategory[catId]; }
    function productCount() external view returns (uint256) { return _nextProductId - 1; }

    // =========================================================================
    // ORDER DOMAIN
    // =========================================================================

    function createOrder(uint256 userId, uint256 orgId, uint256 totalCents, string calldata shippingAddress, bytes32 couponCode, uint256 taxBps) external userExists(userId) returns (uint256 id) {
        require(_users[userId].active, "LC: user inactive");
        _pos(totalCents, "total");
        _ne(shippingAddress, "shippingAddress");

        uint256 couponId = couponCode != bytes32(0) ? _couponByCode[couponCode] : 0;
        uint256 discountCents = _applyDiscount(totalCents, couponId);
        uint256 taxCents = _calculateTax(totalCents - discountCents, taxBps);

        id = _nextOrderId++;
        _orders[id] = Order({ id: id, userId: userId, orgId: orgId, totalCents: totalCents, discountCents: discountCents, taxCents: taxCents, shippingCents: 0, status: OrderStatus.Pending, couponCode: couponCode, shippingAddress: shippingAddress, billingAddress: "", createdAt: block.timestamp, updatedAt: block.timestamp });
        _ordersByUser[userId].push(id);

        if (couponCode != bytes32(0)) emit CouponUsed(couponCode, id);
        _audit(keccak256("ORDER_CREATE"), keccak256("Order"), id, abi.encode(userId, totalCents));
        emit OrderCreated(id, userId, totalCents);
    }

    function addOrderLine(uint256 orderId, uint256 productId, uint256 qty, uint256 unitPriceCents) external orderExists(orderId) productExists(productId) returns (uint256 lineId) {
        require(_orders[orderId].status == OrderStatus.Pending, "LC: order not pending");
        _pos(qty, "qty");
        _pos(unitPriceCents, "unitPrice");

        lineId = _nextLineId++;
        _lines[lineId] = OrderLine({ id: lineId, orderId: orderId, productId: productId, qty: qty, unitPriceCents: unitPriceCents, discountCents: 0, taxCents: 0 });
        _linesByOrder[orderId].push(lineId);
        emit OrderLineAdded(orderId, lineId);
    }

    function updateOrderStatus(uint256 id, OrderStatus status) external orderExists(id) {
        require(_orders[id].status != OrderStatus.Cancelled, "LC: cancelled");
        _orders[id].status = status;
        _orders[id].updatedAt = block.timestamp;
        if (status == OrderStatus.Delivered) {
            _grantLoyaltyPoints(_orders[id].userId, _orders[id].totalCents - _orders[id].discountCents);
        }
        _audit(keccak256("ORDER_STATUS"), keccak256("Order"), id, abi.encode(uint8(status)));
        emit OrderUpdated(id, status);
    }

    function cancelOrder(uint256 id) external orderExists(id) {
        require(_orders[id].status == OrderStatus.Pending || _orders[id].status == OrderStatus.Confirmed, "LC: not cancellable");
        _orders[id].status = OrderStatus.Cancelled;
        _orders[id].updatedAt = block.timestamp;
        _audit(keccak256("ORDER_CANCEL"), keccak256("Order"), id, "");
        emit OrderUpdated(id, OrderStatus.Cancelled);
    }

    function getOrder(uint256 id) external view orderExists(id) returns (Order memory) { return _orders[id]; }
    function getOrderLines(uint256 orderId) external view returns (uint256[] memory) { return _linesByOrder[orderId]; }
    function getOrderLine(uint256 id) external view returns (OrderLine memory) { require(_lines[id].id != 0, "LC: not found"); return _lines[id]; }
    function getOrdersByUser(uint256 userId) external view returns (uint256[] memory) { return _ordersByUser[userId]; }
    function orderCount() external view returns (uint256) { return _nextOrderId - 1; }

    // =========================================================================
    // REVIEW DOMAIN
    // =========================================================================

    function createReview(uint256 productId, uint256 userId, uint8 rating, string calldata title, string calldata body) external productExists(productId) userExists(userId) returns (uint256 id) {
        require(rating >= 1 && rating <= 5, "LC: invalid rating");
        _ne(title, "title");

        id = _nextReviewId++;
        _reviews[id] = Review({ id: id, productId: productId, userId: userId, rating: rating, title: title, body: body, verified: false, flagged: false, helpfulVotes: 0, unhelpfulVotes: 0, createdAt: block.timestamp });
        _reviewsByProduct[productId].push(id);
        _audit(keccak256("REVIEW_CREATE"), keccak256("Review"), id, abi.encode(productId, userId, rating));
        emit ReviewCreated(id, productId);
    }

    function flagReview(uint256 id) external {
        require(_reviews[id].id != 0, "LC: review not found");
        _reviews[id].flagged = true;
        emit ReviewFlagged(id);
    }

    function verifyReview(uint256 id) external onlyOwner {
        require(_reviews[id].id != 0, "LC: review not found");
        _reviews[id].verified = true;
        _reviews[id].flagged = false;
    }

    function voteReview(uint256 id, bool helpful) external {
        require(_reviews[id].id != 0, "LC: review not found");
        if (helpful) _reviews[id].helpfulVotes++; else _reviews[id].unhelpfulVotes++;
    }

    function deleteReview(uint256 id) external onlyOwner {
        require(_reviews[id].id != 0, "LC: review not found");
        delete _reviews[id];
        emit ReviewDeleted(id);
    }

    function getReview(uint256 id) external view returns (Review memory) { require(_reviews[id].id != 0, "LC: not found"); return _reviews[id]; }
    function getReviewsByProduct(uint256 productId) external view returns (uint256[] memory) { return _reviewsByProduct[productId]; }

    function getProductRatingStats(uint256 productId) external view returns (uint256 avg, uint256 count, uint256 totalVotes) {
        uint256[] storage ids = _reviewsByProduct[productId];
        count = ids.length;
        if (count == 0) return (0, 0, 0);
        uint256 sum = 0;
        for (uint256 i = 0; i < count; i++) {
            Review storage r = _reviews[ids[i]];
            sum += r.rating;
            totalVotes += r.helpfulVotes + r.unhelpfulVotes;
        }
        avg = sum / count;
    }

    // =========================================================================
    // INVENTORY DOMAIN
    // =========================================================================

    function logInventory(uint256 productId, int256 delta, string calldata reason, bytes32 extRef) external productExists(productId) returns (uint256 id) {
        require(delta != 0, "LC: zero delta");
        if (delta < 0) {
            uint256 dec = uint256(-delta);
            uint256 available = _products[productId].stock > _products[productId].reservedStock ? _products[productId].stock - _products[productId].reservedStock : 0;
            require(available >= dec, "LC: insufficient stock");
            _products[productId].stock -= dec;
        } else {
            _products[productId].stock += uint256(delta);
        }

        id = _nextInventoryId++;
        _inventory[id] = Inventory({ id: id, productId: productId, delta: delta, newStock: _products[productId].stock, reason: reason, externalRef: extRef, updatedBy: msg.sender, timestamp: block.timestamp });
        _audit(keccak256("INV_LOG"), keccak256("Inventory"), id, abi.encode(productId, delta));
        emit InventoryLogged(id, productId, delta);
    }

    function batchLogInventory(uint256[] calldata productIds, int256[] calldata deltas, bytes32[] calldata refs) external {
        require(productIds.length == deltas.length && productIds.length == refs.length && productIds.length <= 50, "LC: bad batch");
        for (uint256 i = 0; i < productIds.length; i++) {
            require(_products[productIds[i]].id != 0, "LC: product not found");
            if (deltas[i] < 0) {
                uint256 dec = uint256(-deltas[i]);
                require(_products[productIds[i]].stock >= dec, "LC: insufficient stock");
                _products[productIds[i]].stock -= dec;
            } else {
                _products[productIds[i]].stock += uint256(deltas[i]);
            }
            uint256 iid = _nextInventoryId++;
            _inventory[iid] = Inventory({ id: iid, productId: productIds[i], delta: deltas[i], newStock: _products[productIds[i]].stock, reason: "batch", externalRef: refs[i], updatedBy: msg.sender, timestamp: block.timestamp });
            emit InventoryLogged(iid, productIds[i], deltas[i]);
        }
    }

    function getInventoryLog(uint256 id) external view returns (Inventory memory) { require(_inventory[id].id != 0, "LC: not found"); return _inventory[id]; }

    // =========================================================================
    // SHIPMENT DOMAIN
    // =========================================================================

    function createShipment(uint256 orderId, string calldata carrier, string calldata trackingNumber, uint256 estimatedDelivery, uint256 weightGrams) external orderExists(orderId) returns (uint256 id) {
        _ne(carrier, "carrier");
        _ne(trackingNumber, "tracking");

        id = _nextShipmentId++;
        _shipments[id] = Shipment({ id: id, orderId: orderId, carrier: carrier, trackingNumber: trackingNumber, status: ShipmentStatus.Created, weightGrams: weightGrams, estimatedDelivery: estimatedDelivery, actualDelivery: 0, notes: "", createdAt: block.timestamp });
        _shipmentsByOrder[orderId].push(id);
        _audit(keccak256("SHIP_CREATE"), keccak256("Shipment"), id, abi.encode(orderId, carrier));
        emit ShipmentCreated(id, orderId);
    }

    function updateShipment(uint256 id, ShipmentStatus status, string calldata notes) external {
        require(_shipments[id].id != 0, "LC: shipment not found");
        _shipments[id].status = status;
        _shipments[id].notes = notes;
        if (status == ShipmentStatus.Delivered) _shipments[id].actualDelivery = block.timestamp;
        _audit(keccak256("SHIP_UPDATE"), keccak256("Shipment"), id, abi.encode(uint8(status)));
        emit ShipmentUpdated(id, status);
    }

    function getShipment(uint256 id) external view returns (Shipment memory) { require(_shipments[id].id != 0, "LC: not found"); return _shipments[id]; }
    function getShipmentsByOrder(uint256 orderId) external view returns (uint256[] memory) { return _shipmentsByOrder[orderId]; }

    // =========================================================================
    // PAYMENT DOMAIN
    // =========================================================================

    function createPayment(uint256 orderId, uint256 amountCents, bytes32 txHash, bytes32 gatewayRef, string calldata method) external orderExists(orderId) returns (uint256 id) {
        _pos(amountCents, "amount");

        id = _nextPaymentId++;
        _payments[id] = Payment({ id: id, orderId: orderId, userId: _orders[orderId].userId, amountCents: amountCents, status: PaymentStatus.Unpaid, txHash: txHash, gatewayRef: gatewayRef, payer: msg.sender, method: method, paidAt: 0, createdAt: block.timestamp });
        _paymentsByOrder[orderId].push(id);
        _audit(keccak256("PAY_CREATE"), keccak256("Payment"), id, abi.encode(orderId, amountCents));
        emit PaymentCreated(id, orderId);
    }

    function authorisePayment(uint256 id) external {
        require(_payments[id].id != 0, "LC: payment not found");
        require(_payments[id].status == PaymentStatus.Unpaid, "LC: not unpaid");
        _payments[id].status = PaymentStatus.Authorised;
        emit PaymentUpdated(id, PaymentStatus.Authorised);
    }

    function capturePayment(uint256 id) external {
        require(_payments[id].id != 0, "LC: payment not found");
        require(_payments[id].status == PaymentStatus.Authorised, "LC: not authorised");
        _payments[id].status = PaymentStatus.Captured;
        _payments[id].paidAt = block.timestamp;
        _audit(keccak256("PAY_CAPTURE"), keccak256("Payment"), id, "");
        emit PaymentUpdated(id, PaymentStatus.Captured);
    }

    function voidPayment(uint256 id) external {
        require(_payments[id].id != 0, "LC: payment not found");
        require(_payments[id].status == PaymentStatus.Authorised, "LC: not authorised");
        _payments[id].status = PaymentStatus.Voided;
        emit PaymentUpdated(id, PaymentStatus.Voided);
    }

    function getPayment(uint256 id) external view returns (Payment memory) { require(_payments[id].id != 0, "LC: not found"); return _payments[id]; }
    function getPaymentsByOrder(uint256 orderId) external view returns (uint256[] memory) { return _paymentsByOrder[orderId]; }

    function getTotalPaidForOrder(uint256 orderId) external view returns (uint256 total) {
        uint256[] storage ids = _paymentsByOrder[orderId];
        for (uint256 i = 0; i < ids.length; i++) {
            if (_payments[ids[i]].status == PaymentStatus.Captured) {
                total += _payments[ids[i]].amountCents;
            }
        }
    }

    // =========================================================================
    // REFUND DOMAIN
    // =========================================================================

    function requestRefund(uint256 orderId, uint256 paymentId, uint256 amountCents, string calldata reason) external orderExists(orderId) returns (uint256 id) {
        require(_payments[paymentId].id != 0 && _payments[paymentId].status == PaymentStatus.Captured, "LC: payment not captured");
        _pos(amountCents, "amount");
        require(amountCents <= _payments[paymentId].amountCents, "LC: exceeds payment");

        id = _nextRefundId++;
        _refunds[id] = Refund({ id: id, orderId: orderId, paymentId: paymentId, amountCents: amountCents, status: RefundStatus.Requested, reason: reason, requestedBy: msg.sender, processedBy: address(0), createdAt: block.timestamp, processedAt: 0 });
        _refundsByOrder[orderId].push(id);
        _audit(keccak256("REFUND_REQ"), keccak256("Refund"), id, abi.encode(orderId, amountCents));
        emit RefundRequested(id, orderId);
    }

    function reviewRefund(uint256 id, RefundStatus decision) external onlyOwner {
        require(_refunds[id].id != 0, "LC: refund not found");
        require(_refunds[id].status == RefundStatus.Requested, "LC: already reviewed");
        require(decision == RefundStatus.Approved || decision == RefundStatus.Rejected, "LC: invalid decision");
        _refunds[id].status = decision;
        _refunds[id].processedBy = msg.sender;
        _refunds[id].processedAt = block.timestamp;
        _audit(keccak256("REFUND_REVIEW"), keccak256("Refund"), id, abi.encode(uint8(decision)));
        emit RefundProcessed(id, decision);
    }

    function processRefund(uint256 id) external onlyOwner {
        require(_refunds[id].id != 0, "LC: refund not found");
        require(_refunds[id].status == RefundStatus.Approved, "LC: not approved");
        _refunds[id].status = RefundStatus.Processed;
        _refunds[id].processedAt = block.timestamp;
        emit RefundProcessed(id, RefundStatus.Processed);
    }

    function getRefund(uint256 id) external view returns (Refund memory) { require(_refunds[id].id != 0, "LC: not found"); return _refunds[id]; }

    // =========================================================================
    // COUPON DOMAIN
    // =========================================================================

    function createCoupon(bytes32 code, CouponType couponType, uint256 value, uint256 minOrderCents, uint256 maxUsages, uint256 expiresAt) external onlyOwner returns (uint256 id) {
        require(_couponByCode[code] == 0, "LC: code exists");
        _pos(value, "value");
        require(expiresAt > block.timestamp, "LC: already expired");
        if (couponType == CouponType.Percentage) require(value <= 10000, "LC: bps > 10000");

        id = _nextCouponId++;
        _coupons[id] = Coupon({ id: id, code: code, couponType: couponType, value: value, minOrderCents: minOrderCents, maxUsages: maxUsages, usageCount: 0, expiresAt: expiresAt, active: true, createdAt: block.timestamp });
        _couponByCode[code] = id;
        _audit(keccak256("COUPON_CREATE"), keccak256("Coupon"), id, abi.encode(code, value));
        emit CouponCreated(id, code);
    }

    function deactivateCoupon(uint256 id) external onlyOwner {
        require(_coupons[id].id != 0, "LC: coupon not found");
        _coupons[id].active = false;
        emit CouponDeactivated(id);
    }

    function getCoupon(uint256 id) external view returns (Coupon memory) { require(_coupons[id].id != 0, "LC: not found"); return _coupons[id]; }
    function getCouponByCode(bytes32 code) external view returns (Coupon memory) { uint256 id = _couponByCode[code]; require(id != 0, "LC: not found"); return _coupons[id]; }

    // =========================================================================
    // SUBSCRIPTION DOMAIN
    // =========================================================================

    function createSubscription(uint256 userId, uint256 planId, uint256 amountCents, uint256 periodStart, uint256 periodEnd) external userExists(userId) returns (uint256 id) {
        _pos(amountCents, "amount");
        require(periodEnd > periodStart, "LC: invalid period");

        id = _nextSubId++;
        _subscriptions[id] = Subscription({ id: id, userId: userId, planId: planId, status: SubscriptionStatus.Active, periodStart: periodStart, periodEnd: periodEnd, amountCents: amountCents, renewalCount: 0, createdAt: block.timestamp, updatedAt: block.timestamp });
        _subscriptionsByUser[userId].push(id);
        _audit(keccak256("SUB_CREATE"), keccak256("Subscription"), id, abi.encode(userId, planId));
        emit SubscriptionCreated(id, userId);
    }

    function renewSubscription(uint256 id, uint256 newPeriodEnd) external {
        require(_subscriptions[id].id != 0, "LC: sub not found");
        require(_subscriptions[id].status == SubscriptionStatus.Active, "LC: not active");
        require(newPeriodEnd > _subscriptions[id].periodEnd, "LC: invalid period");
        _subscriptions[id].periodEnd = newPeriodEnd;
        _subscriptions[id].renewalCount++;
        _subscriptions[id].updatedAt = block.timestamp;
        _audit(keccak256("SUB_RENEW"), keccak256("Subscription"), id, abi.encode(newPeriodEnd));
        emit SubscriptionRenewed(id);
    }

    function cancelSubscription(uint256 id) external {
        require(_subscriptions[id].id != 0, "LC: sub not found");
        require(_subscriptions[id].status == SubscriptionStatus.Active || _subscriptions[id].status == SubscriptionStatus.Paused, "LC: not cancellable");
        _subscriptions[id].status = SubscriptionStatus.Cancelled;
        _subscriptions[id].updatedAt = block.timestamp;
        emit SubscriptionCancelled(id);
    }

    function pauseSubscription(uint256 id) external {
        require(_subscriptions[id].id != 0, "LC: sub not found");
        require(_subscriptions[id].status == SubscriptionStatus.Active, "LC: not active");
        _subscriptions[id].status = SubscriptionStatus.Paused;
        _subscriptions[id].updatedAt = block.timestamp;
    }

    function getSubscription(uint256 id) external view returns (Subscription memory) { require(_subscriptions[id].id != 0, "LC: not found"); return _subscriptions[id]; }
    function getSubscriptionsByUser(uint256 userId) external view returns (uint256[] memory) { return _subscriptionsByUser[userId]; }

    // =========================================================================
    // SUPPORT TICKET DOMAIN
    // =========================================================================

    function createTicket(uint256 userId, uint256 orderId, TicketPriority priority, string calldata subject, string calldata body) external userExists(userId) returns (uint256 id) {
        _ne(subject, "subject");

        id = _nextTicketId++;
        _tickets[id] = SupportTicket({ id: id, userId: userId, orderId: orderId, priority: priority, status: TicketStatus.Open, subject: subject, body: body, assignedTo: address(0), resolvedAt: 0, createdAt: block.timestamp, updatedAt: block.timestamp });
        _ticketsByUser[userId].push(id);
        _audit(keccak256("TICKET_CREATE"), keccak256("Ticket"), id, abi.encode(userId, uint8(priority)));
        emit TicketCreated(id, userId);
    }

    function assignTicket(uint256 id, address agent) external onlyOwner {
        require(_tickets[id].id != 0, "LC: ticket not found");
        _tickets[id].assignedTo = agent;
        _tickets[id].status = TicketStatus.InProgress;
        _tickets[id].updatedAt = block.timestamp;
        emit TicketAssigned(id, agent);
    }

    function updateTicketStatus(uint256 id, TicketStatus status) external {
        require(_tickets[id].id != 0, "LC: ticket not found");
        _tickets[id].status = status;
        _tickets[id].updatedAt = block.timestamp;
        if (status == TicketStatus.Resolved || status == TicketStatus.Closed) {
            _tickets[id].resolvedAt = block.timestamp;
        }
        _audit(keccak256("TICKET_UPDATE"), keccak256("Ticket"), id, abi.encode(uint8(status)));
        emit TicketUpdated(id, status);
    }

    function escalateTicket(uint256 id) external {
        require(_tickets[id].id != 0, "LC: ticket not found");
        _tickets[id].status = TicketStatus.Escalated;
        _tickets[id].priority = TicketPriority.Critical;
        _tickets[id].updatedAt = block.timestamp;
        emit TicketUpdated(id, TicketStatus.Escalated);
    }

    function getTicket(uint256 id) external view returns (SupportTicket memory) { require(_tickets[id].id != 0, "LC: not found"); return _tickets[id]; }
    function getTicketsByUser(uint256 userId) external view returns (uint256[] memory) { return _ticketsByUser[userId]; }

    // =========================================================================
    // NOTIFICATION DOMAIN
    // =========================================================================

    function sendNotification(uint256 userId, string calldata channel, string calldata subject, string calldata body) external userExists(userId) returns (uint256 id) {
        id = _createNotification(userId, channel, subject, body);
        _notifications[id].sent = true;
        _notifications[id].sentAt = block.timestamp;
        emit NotificationSent(id);
    }

    function markNotificationRead(uint256 id) external {
        require(_notifications[id].id != 0, "LC: notif not found");
        _notifications[id].read = true;
    }

    function getNotification(uint256 id) external view returns (Notification memory) { require(_notifications[id].id != 0, "LC: not found"); return _notifications[id]; }
    function getNotificationsByUser(uint256 userId) external view returns (uint256[] memory) { return _notificationsByUser[userId]; }

    // =========================================================================
    // AUDIT DOMAIN
    // =========================================================================

    function getAudit(uint256 id) external view returns (Audit memory) { require(_audits[id].id != 0, "LC: not found"); return _audits[id]; }
    function auditCount() external view returns (uint256) { return _nextAuditId - 1; }

    // =========================================================================
    // COMPLEX AGGREGATE QUERIES
    // =========================================================================

    function getOrderFullSummary(uint256 orderId) external view orderExists(orderId) returns (
        Order memory order,
        uint256 lineCount,
        uint256 paymentCount,
        uint256 shipmentCount,
        uint256 refundCount,
        uint256 totalPaid,
        uint256 totalRefunded
    ) {
        order = _orders[orderId];
        lineCount = _linesByOrder[orderId].length;

        uint256[] storage pids = _paymentsByOrder[orderId];
        paymentCount = pids.length;
        for (uint256 i = 0; i < pids.length; i++) {
            if (_payments[pids[i]].status == PaymentStatus.Captured) totalPaid += _payments[pids[i]].amountCents;
        }

        shipmentCount = _shipmentsByOrder[orderId].length;

        uint256[] storage rids = _refundsByOrder[orderId];
        refundCount = rids.length;
        for (uint256 i = 0; i < rids.length; i++) {
            if (_refunds[rids[i]].status == RefundStatus.Processed) totalRefunded += _refunds[rids[i]].amountCents;
        }
    }

    function getUserDashboard(uint256 userId) external view userExists(userId) returns (
        uint256 totalOrders,
        uint256 totalSpentCents,
        uint256 loyaltyPoints,
        uint256 activeSubscriptions,
        uint256 openTickets
    ) {
        loyaltyPoints = _users[userId].loyaltyPoints;
        totalOrders = _ordersByUser[userId].length;

        uint256[] storage oids = _ordersByUser[userId];
        for (uint256 i = 0; i < oids.length; i++) {
            if (_orders[oids[i]].status == OrderStatus.Delivered) {
                totalSpentCents += _orders[oids[i]].totalCents - _orders[oids[i]].discountCents;
            }
        }

        uint256[] storage sids = _subscriptionsByUser[userId];
        for (uint256 i = 0; i < sids.length; i++) {
            if (_subscriptions[sids[i]].status == SubscriptionStatus.Active) activeSubscriptions++;
        }

        uint256[] storage tids = _ticketsByUser[userId];
        for (uint256 i = 0; i < tids.length; i++) {
            TicketStatus ts = _tickets[tids[i]].status;
            if (ts == TicketStatus.Open || ts == TicketStatus.InProgress || ts == TicketStatus.Escalated) openTickets++;
        }
    }

    function getCategoryStats(uint256 categoryId) external view returns (
        uint256 productCount_,
        uint256 totalStock,
        uint256 availableCount,
        uint256 avgPriceCents
    ) {
        uint256[] storage pids = _productsByCategory[categoryId];
        productCount_ = pids.length;
        if (productCount_ == 0) return (0, 0, 0, 0);

        uint256 priceSum = 0;
        for (uint256 i = 0; i < pids.length; i++) {
            Product storage p = _products[pids[i]];
            if (p.id == 0) continue;
            totalStock += p.stock;
            if (p.available) availableCount++;
            priceSum += p.priceCents;
        }
        avgPriceCents = priceSum / productCount_;
    }

    function getRevenueStats(uint256[] calldata orderIds) external view returns (
        uint256 grossRevenue,
        uint256 discounts,
        uint256 taxes,
        uint256 netRevenue,
        uint256 deliveredCount
    ) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage o = _orders[orderIds[i]];
            if (o.id == 0) continue;
            grossRevenue += o.totalCents;
            discounts += o.discountCents;
            taxes += o.taxCents;
            if (o.status == OrderStatus.Delivered) {
                netRevenue += o.totalCents - o.discountCents;
                deliveredCount++;
            }
        }
    }
}
