// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleMultiSig {
    mapping(address => bool) public owners;
    address[] public ownersList;
    uint256 public threshold;
    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;

    //[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0x5B38Da6a701c568545dCfcB03FcB875f56beddC4],2
    
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        mapping(address => bool) confirmations;
        uint256 confirmationCount;
        bool executed;
    }

    event TransactionProposed(uint256 indexed transactionId, address indexed proposer, address to, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed confirmer);
    event TransactionExecuted(uint256 indexed transactionId);
    event Deposit(address indexed sender, uint256 amount, uint256 balance);

    modifier onlyOwner() {
        require(owners[msg.sender], "Only owners can call this function");
        _;
    }

    constructor(address[] memory _owners, uint256 _threshold) {
        require(_owners.length > 0, "At least one owner is required");
        require(_threshold > 0 && _threshold <= _owners.length, "Invalid threshold");
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Owner address cannot be zero");
            owners[owner] = true;
        }
        ownersList = _owners;
        threshold = _threshold;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function proposeTransaction(address to, uint256 value, bytes calldata data) external onlyOwner {
        uint256 transactionId = transactionCount++;
        Transaction storage transaction = transactions[transactionId];
        transaction.to = to;
        transaction.value = value;
        transaction.data = data;
        transaction.confirmationCount = 1; // Proposer's confirmation
        transaction.executed = false;
        transaction.confirmations[msg.sender] = true;
        emit TransactionProposed(transactionId, msg.sender, to, value, data);
    }

    function confirmTransaction(uint256 transactionId) external onlyOwner {
        require(transactionId < transactionCount, "Invalid transaction ID");
        Transaction storage transaction = transactions[transactionId];
        require(!transaction.executed, "Transaction has already been executed");
        require(!transaction.confirmations[msg.sender], "You have already confirmed this transaction");
        transaction.confirmations[msg.sender] = true;
        transaction.confirmationCount++;
        //autoExecuteTransaction(transactionId);
        emit TransactionConfirmed(transactionId, msg.sender);
    }

    function executeTransaction(uint256 transactionId) public {
        require(transactionId < transactionCount, "Invalid transaction ID");
        Transaction storage transaction = transactions[transactionId];
        require(!transaction.executed, "Transaction has already been executed");
        require(transaction.confirmationCount >= threshold, "Not enough confirmations");
        require(address(this).balance >= transaction.value, "Insufficient funds");
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction execution failed");
        transaction.executed = true;
        emit TransactionExecuted(transactionId);
    }

    function autoExecuteTransaction(uint256 transactionId) internal {
        Transaction storage transaction = transactions[transactionId];
        if (transaction.confirmationCount >= threshold) {
            executeTransaction(transactionId);
        }
    }

    function getTransaction(uint256 transactionId) external view returns (address to, uint256 value, bytes memory data, uint256 confirmationCount, bool executed) {
        require(transactionId < transactionCount, "Invalid transaction ID");
        Transaction storage transaction = transactions[transactionId];
        return (transaction.to, transaction.value, transaction.data, transaction.confirmationCount, transaction.executed);
    }

    function getOwners() external view returns (address[] memory) {
        return ownersList;
    }

    function getThreshold() external view returns (uint256) {
        return threshold;
    }

    function getConfirmations(uint256 transactionId) external view returns (address[] memory) {
        require(transactionId < transactionCount, "Invalid transaction ID");
        Transaction storage transaction = transactions[transactionId];
        address[] memory confirmers = new address[](ownersList.length);
        uint256 count = 0;
        for (uint256 i = 0; i < ownersList.length; i++) {
            address owner = ownersList[i];
            if (transaction.confirmations[owner]) {
                confirmers[count] = owner;
                count++;
            }
        }
        address[] memory actualConfirmers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            actualConfirmers[i] = confirmers[i];
        }
        return actualConfirmers;
    }
}   