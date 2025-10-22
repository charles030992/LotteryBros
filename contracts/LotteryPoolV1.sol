// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract LotteryPoolV1 {
    // Minimal reentrancy guard
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    struct Contribution {
        uint256 amount;
        uint256 timestamp;
        bool approved;
    }

    struct LotteryPurchase {
        uint256 amount;
        uint256 timestamp;
        string description;
        address purchasedBy;
        bool reimbursed;
    }

    address[] public members;
    uint256 public requiredApprovals;
    uint256 public monthlyContribution;

    mapping(address => Contribution[]) public contributions;
    mapping(address => bool) public isMember;
    mapping(address => mapping(uint256 => mapping(address => bool))) public approvals;

    LotteryPurchase[] public lotteryPurchases;

    event ContributionMade(address indexed member, uint256 amount, uint256 index);
    event ContributionApproved(address indexed approver, address indexed member, uint256 contributionId);
    event LotteryPurchased(address indexed purchaser, uint256 amount, string description, uint256 purchaseId);
    event Reimbursement(address indexed purchaser, uint256 amount, uint256 purchaseId);
    event MemberAdded(address indexed newMember);
    event MemberRemoved(address indexed removedMember);

    modifier onlyMember() {
        require(isMember[msg.sender], "Solo miembros");
        _;
    }

    constructor(address[] memory _members, uint256 _monthlyContribution, uint256 _requiredApprovals) {
        require(_members.length > 0, "Se necesita al menos 1 miembro");
        require(_requiredApprovals > 0 && _requiredApprovals <= _members.length, "Aprobaciones invalidas");

        for (uint i = 0; i < _members.length; i++) {
            members.push(_members[i]);
            isMember[_members[i]] = true;
        }

    monthlyContribution = _monthlyContribution;
    requiredApprovals = _requiredApprovals;
        _status = _NOT_ENTERED;
    }

    function contribute() external payable onlyMember {
        require(msg.value == monthlyContribution, "Monto incorrecto");
        contributions[msg.sender].push(Contribution({
            amount: msg.value,
            timestamp: block.timestamp,
            approved: false
        }));
        uint256 index = contributions[msg.sender].length - 1;
        emit ContributionMade(msg.sender, msg.value, index);
    }

    function approveContribution(address member, uint256 contributionId) external onlyMember {
        require(member != address(0), "Member invalido");
        require(contributionId < contributions[member].length, "Contribucion no existe");
        require(!contributions[member][contributionId].approved, "Ya aprobada");
        require(!approvals[member][contributionId][msg.sender], "Ya aprobaste");

        approvals[member][contributionId][msg.sender] = true;

        if (getApprovalCount(member, contributionId) >= requiredApprovals) {
            contributions[member][contributionId].approved = true;
        }

        emit ContributionApproved(msg.sender, member, contributionId);
    }

    function purchaseLottery(uint256 amount, string memory description) external onlyMember nonReentrant {
        require(hasApprovedContributions(msg.sender), "Debes tener contribuciones aprobadas");
        require(amount <= address(this).balance, "Fondos insuficientes");

        lotteryPurchases.push(LotteryPurchase({
            amount: amount,
            timestamp: block.timestamp,
            description: description,
            purchasedBy: msg.sender,
            reimbursed: false
        }));
        uint256 purchaseId = lotteryPurchases.length - 1;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Transfer failed");

        emit LotteryPurchased(msg.sender, amount, description, purchaseId);
    }

    function reimburse(uint256 purchaseId, uint256 amount) external onlyMember nonReentrant {
        require(purchaseId < lotteryPurchases.length, "Compra no existe");
        LotteryPurchase storage p = lotteryPurchases[purchaseId];
        require(!p.reimbursed, "Ya reembolsado");
        require(p.purchasedBy == msg.sender, "No eres comprador");
        require(amount <= p.amount, "Monto mayor al gastado");

        p.reimbursed = true;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Transfer failed");

        emit Reimbursement(msg.sender, amount, purchaseId);
    }

    function getApprovalCount(address member, uint256 contributionId) public view returns (uint256) {
        uint256 count = 0;
        for (uint i = 0; i < members.length; i++) {
            if (approvals[member][contributionId][members[i]]) {
                count++;
            }
        }
        return count;
    }

    function hasApprovedContributions(address member) public view returns (bool) {
        for (uint i = 0; i < contributions[member].length; i++) {
            if (contributions[member][i].approved) {
                return true;
            }
        }
        return false;
    }

    function getPoolBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getMemberCount() public view returns (uint256) {
        return members.length;
    }

    function addMember(address newMember) external onlyMember {
        require(!isMember[newMember], "Ya miembro");
        members.push(newMember);
        isMember[newMember] = true;
        emit MemberAdded(newMember);
    }

    function removeMember(address memberToRemove) external onlyMember {
        require(isMember[memberToRemove], "No es miembro");
        isMember[memberToRemove] = false;
        emit MemberRemoved(memberToRemove);
    }

    receive() external payable {}
}
