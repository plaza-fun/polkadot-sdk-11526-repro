// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SmallContract - Control group (~10KB deployed bytecode)
/// @notice Basic CRUD for User and Order entities. Expected to deploy successfully on both EVM and PVM.
contract SmallContract {
    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    struct User {
        uint256 id;
        address wallet;
        string name;
        string email;
        bool active;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Order {
        uint256 id;
        uint256 userId;
        bytes32 ref;
        uint256 amount;
        uint8 status; // 0=pending, 1=confirmed, 2=shipped, 3=delivered, 4=cancelled
        uint256 createdAt;
        uint256 updatedAt;
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(uint256 => User) private users;
    mapping(uint256 => Order) private orders;
    mapping(address => uint256) private userIdByWallet;
    mapping(uint256 => uint256[]) private ordersByUser;

    uint256 private nextUserId = 1;
    uint256 private nextOrderId = 1;

    address public owner;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event UserCreated(uint256 indexed userId, address indexed wallet, string name);
    event UserUpdated(uint256 indexed userId, string name);
    event UserDeleted(uint256 indexed userId);

    event OrderCreated(uint256 indexed orderId, uint256 indexed userId, uint256 amount);
    event OrderUpdated(uint256 indexed orderId, uint8 status);
    event OrderDeleted(uint256 indexed orderId);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "SmallContract: not owner");
        _;
    }

    modifier userExists(uint256 userId) {
        require(users[userId].id != 0, "SmallContract: user not found");
        _;
    }

    modifier orderExists(uint256 orderId) {
        require(orders[orderId].id != 0, "SmallContract: order not found");
        _;
    }

    // -------------------------------------------------------------------------
    // User CRUD
    // -------------------------------------------------------------------------

    function createUser(
        address wallet,
        string calldata name,
        string calldata email
    ) external returns (uint256 userId) {
        require(wallet != address(0), "SmallContract: zero address");
        require(bytes(name).length > 0, "SmallContract: empty name");
        require(userIdByWallet[wallet] == 0, "SmallContract: wallet already registered");

        userId = nextUserId++;
        users[userId] = User({
            id: userId,
            wallet: wallet,
            name: name,
            email: email,
            active: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        userIdByWallet[wallet] = userId;

        emit UserCreated(userId, wallet, name);
    }

    function getUser(uint256 userId) external view userExists(userId) returns (User memory) {
        return users[userId];
    }

    function getUserByWallet(address wallet) external view returns (User memory) {
        uint256 userId = userIdByWallet[wallet];
        require(userId != 0, "SmallContract: wallet not registered");
        return users[userId];
    }

    function updateUser(
        uint256 userId,
        string calldata name,
        string calldata email
    ) external userExists(userId) {
        require(bytes(name).length > 0, "SmallContract: empty name");
        User storage u = users[userId];
        u.name = name;
        u.email = email;
        u.updatedAt = block.timestamp;
        emit UserUpdated(userId, name);
    }

    function deactivateUser(uint256 userId) external onlyOwner userExists(userId) {
        users[userId].active = false;
        users[userId].updatedAt = block.timestamp;
        emit UserDeleted(userId);
    }

    // -------------------------------------------------------------------------
    // Order CRUD
    // -------------------------------------------------------------------------

    function createOrder(
        uint256 userId,
        bytes32 ref,
        uint256 amount
    ) external userExists(userId) returns (uint256 orderId) {
        require(amount > 0, "SmallContract: zero amount");
        require(users[userId].active, "SmallContract: user inactive");

        orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            userId: userId,
            ref: ref,
            amount: amount,
            status: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        ordersByUser[userId].push(orderId);

        emit OrderCreated(orderId, userId, amount);
    }

    function getOrder(uint256 orderId) external view orderExists(orderId) returns (Order memory) {
        return orders[orderId];
    }

    function getOrdersByUser(uint256 userId) external view userExists(userId) returns (uint256[] memory) {
        return ordersByUser[userId];
    }

    function updateOrderStatus(
        uint256 orderId,
        uint8 newStatus
    ) external orderExists(orderId) {
        require(newStatus <= 4, "SmallContract: invalid status");
        Order storage o = orders[orderId];
        require(o.status != 4, "SmallContract: order already cancelled");
        o.status = newStatus;
        o.updatedAt = block.timestamp;
        emit OrderUpdated(orderId, newStatus);
    }

    function cancelOrder(uint256 orderId) external orderExists(orderId) {
        Order storage o = orders[orderId];
        require(o.status == 0, "SmallContract: can only cancel pending orders");
        o.status = 4;
        o.updatedAt = block.timestamp;
        emit OrderUpdated(orderId, 4);
        emit OrderDeleted(orderId);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function userCount() external view returns (uint256) {
        return nextUserId - 1;
    }

    function orderCount() external view returns (uint256) {
        return nextOrderId - 1;
    }

    function isUserActive(uint256 userId) external view returns (bool) {
        return users[userId].active;
    }
}
