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
        bool executed; // indica que los fondos ya fueron transferidos para esta compra
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
        require(msg.sender != member, "No puedes aprobar tu propia contribucion");
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

        // Registrar la propuesta de compra. La ejecución (transferencia) se marca
        // cuando se realiza la transferencia en executePurchase.
        lotteryPurchases.push(LotteryPurchase({
            amount: amount,
            timestamp: block.timestamp,
            description: description,
            purchasedBy: msg.sender,
            executed: false
        }));
        uint256 purchaseId = lotteryPurchases.length - 1;

        emit LotteryPurchased(msg.sender, amount, description, purchaseId);
    }

    // Mapping de aprobaciones para purchases: purchaseApprovals[purchaseId][approver]
    mapping(uint256 => mapping(address => bool)) public purchaseApprovals;

    event PurchaseApproved(address indexed approver, uint256 purchaseId);

    function approvePurchase(uint256 purchaseId) external onlyMember {
        require(purchaseId < lotteryPurchases.length, "Compra no existe");
        require(!purchaseApprovals[purchaseId][msg.sender], "Ya aprobaste compra");
        require(lotteryPurchases[purchaseId].purchasedBy != msg.sender, "No puedes aprobar tu propia compra");

        purchaseApprovals[purchaseId][msg.sender] = true;
        emit PurchaseApproved(msg.sender, purchaseId);
    }

    function getPurchaseApprovalCount(uint256 purchaseId) public view returns (uint256) {
        uint256 count = 0;
        for (uint i = 0; i < members.length; i++) {
            if (purchaseApprovals[purchaseId][members[i]]) {
                count++;
            }
        }
        return count;
    }

    function executePurchase(uint256 purchaseId) external onlyMember nonReentrant {
        require(purchaseId < lotteryPurchases.length, "Compra no existe");
        LotteryPurchase storage p = lotteryPurchases[purchaseId];
        require(!p.executed, "Compra ya ejecutada");
        require(p.amount <= address(this).balance, "Fondos insuficientes");

        // Se requiere que la compra haya sido aprobada por requiredApprovals miembros (sin contar al comprador)
        require(getPurchaseApprovalCount(purchaseId) >= requiredApprovals, "Compra no aprobada por suficientes miembros");

        p.executed = true;
        (bool sent, ) = payable(p.purchasedBy).call{value: p.amount}("");
        require(sent, "Transfer failed");

        emit LotteryPurchased(p.purchasedBy, p.amount, p.description, purchaseId);
    }

    // El comportamiento previo de reimburse permitía que un comprador recibiera
    // fondos dos veces (si primero se le transfería desde purchaseLottery y luego
    // hacía reimburse). Para evitar ese vector de ataque, deshabilitamos la
    // función reimburse y se gestiona la transferencia mediante el flujo de
    // approvePurchase + executePurchase.

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

    // --- Member proposals (se requiere la aprobacion de la mitad+1 de miembros) ---
    struct MemberProposal {
        address member;
        bool add; // true = add, false = remove
        uint256 timestamp;
        bool executed;
    }

    MemberProposal[] public memberProposals;
    mapping(uint256 => mapping(address => bool)) public memberProposalApprovals;

    event MemberProposalCreated(uint256 proposalId, address member, bool add, address proposer);
    event MemberProposalApproved(address indexed approver, uint256 proposalId);

    function proposeAddMember(address newMember) external onlyMember {
        require(newMember != address(0), "Member invalido");
        require(!isMember[newMember], "Ya miembro");

        memberProposals.push(MemberProposal({
            member: newMember,
            add: true,
            timestamp: block.timestamp,
            executed: false
        }));
        uint256 pid = memberProposals.length - 1;
        emit MemberProposalCreated(pid, newMember, true, msg.sender);
    }

    function proposeRemoveMember(address memberToRemove) external onlyMember {
        require(isMember[memberToRemove], "No es miembro");

        memberProposals.push(MemberProposal({
            member: memberToRemove,
            add: false,
            timestamp: block.timestamp,
            executed: false
        }));
        uint256 pid = memberProposals.length - 1;
        emit MemberProposalCreated(pid, memberToRemove, false, msg.sender);
    }

    function approveMemberProposal(uint256 proposalId) external onlyMember {
        require(proposalId < memberProposals.length, "Propuesta no existe");
        MemberProposal storage p = memberProposals[proposalId];
        require(!p.executed, "Propuesta ya ejecutada");
        require(!memberProposalApprovals[proposalId][msg.sender], "Ya aprobaste");

        memberProposalApprovals[proposalId][msg.sender] = true;
        emit MemberProposalApproved(msg.sender, proposalId);

        uint256 count = getMemberProposalApprovalCount(proposalId);
        uint256 majority = (members.length / 2) + 1;
        if (count >= majority) {
            // ejecutar propuesta
            p.executed = true;
            if (p.add) {
                members.push(p.member);
                isMember[p.member] = true;
                emit MemberAdded(p.member);
            } else {
                isMember[p.member] = false;
                emit MemberRemoved(p.member);
            }
        }
    }

    function getMemberProposalApprovalCount(uint256 proposalId) public view returns (uint256) {
        require(proposalId < memberProposals.length, "Propuesta no existe");
        uint256 count = 0;
        for (uint i = 0; i < members.length; i++) {
            if (memberProposalApprovals[proposalId][members[i]]) {
                count++;
            }
        }
        return count;
    }

    receive() external payable {}
}
