// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Name {
    error NotOwner();
    error TxNotExist(uint txId);
    error TxAlreadyApproved(uint txId, address owner);
    error TxAlreadyExecuted(uint txId);
    error NotEnoughApprovals(uint txId);
    error TransferFailed();
    error TxNotApproved(uint txId, address owner);

    event Deposit(address indexed sender, uint amount);
    event Submit(uint indexed txId);
    event Approve(address indexed owner, uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);
    event Execute(uint indexed txId);

    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
    }

    address[] public owners;
    mapping(address owner => bool) public isOwner;
    uint public required; // minimum number of approvals required to execute a transaction

    Transaction[] public transactions;
    mapping(uint transactionIndex => mapping(address owner => bool))
        public approved;

    constructor(address[] memory _owners, uint _required) {
        require(_owners.length > 0, "owners required");
        require(
            _required > 0 && _required <= _owners.length,
            "invalid required number of owners"
        );

        // if the length is too long then it might fail as there is block gas limit
        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner is not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        required = _required;
    }

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NotOwner();
        }
        _;
    }

    modifier txExists(uint _txId) {
        if (_txId >= transactions.length) {
            revert TxNotExist(_txId);
        }
        _;
    }

    modifier notApproved(uint _txId) {
        if (approved[_txId][msg.sender]) {
            revert TxAlreadyApproved(_txId, msg.sender);
        }
        _;
    }

    modifier notExecuted(uint _txId) {
        if (transactions[_txId].executed) {
            revert TxAlreadyExecuted(_txId);
        }
        _;
    }

    function submit(
        address _to,
        uint _value,
        bytes calldata _data
    ) external onlyOwner {
        transactions.push(
            Transaction({to: _to, value: _value, data: _data, executed: false})
        );

        emit Submit(transactions.length - 1);
    }

    function approve(
        uint _txId
    ) external onlyOwner txExists(_txId) notApproved(_txId) notExecuted(_txId) {
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
    }

    function _getApprovalCount(uint _txId) private view returns (uint count) {
        for (uint i = 0; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) {
                count += 1;
            }
        }
    }

    function execute(uint _txId) external txExists(_txId) notExecuted(_txId) {
        if (_getApprovalCount(_txId) < required) {
            revert NotEnoughApprovals(_txId);
        }
        Transaction storage transaction = transactions[_txId];

        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        if (!success) {
            revert TransferFailed();
        }

        emit Execute(_txId);
    }

    function revoke(
        uint _txId
    ) external onlyOwner txExists(_txId) notExecuted(_txId) {
        if (!approved[_txId][msg.sender]) {
            revert TxNotApproved(_txId, msg.sender);
        }

        approved[_txId][msg.sender] = false;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
}
