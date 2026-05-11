// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title MtyldDistributor
 * @notice Quarterly MTYLD distribution contract for Mechanical Temp employees.
 * 
 * How it works:
 * 1. Owner calls distribute(recipients[], amounts[]) with MTYLD pre-approved
 * 2. Contract transfers MTYLD to each recipient in one transaction
 * 3. Emits DistributionExecuted event — fully transparent on Arbiscan
 * 4. Anyone can query distribution history on-chain
 *
 * Alternatively use distributeProportional(recipients[], totalAmount)
 * to auto-calculate each recipient's share based on provided weights.
 */

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract MtyldDistributor is Ownable {

    IERC20 public immutable mtyld;

    // Distribution history
    struct Distribution {
        uint256 timestamp;
        uint256 totalAmount;
        uint256 recipientCount;
        string note; // e.g. "Q1 2026 Employee Distribution"
    }

    Distribution[] public distributions;

    // Track total received per address ever
    mapping(address => uint256) public totalReceived;

    // ── Events ────────────────────────────────────────────────
    event DistributionExecuted(
        uint256 indexed distributionId,
        uint256 totalAmount,
        uint256 recipientCount,
        string note,
        uint256 timestamp
    );

    event RecipientPaid(
        uint256 indexed distributionId,
        address indexed recipient,
        uint256 amount
    );

    event TokensRecovered(address indexed token, uint256 amount);

    constructor(address _mtyld) Ownable(msg.sender) {
        mtyld = IERC20(_mtyld);
    }

    /**
     * @notice Distribute exact amounts to each recipient.
     * @dev Owner must approve this contract for sum(amounts) MTYLD first.
     * @param recipients Array of employee wallet addresses
     * @param amounts Array of MTYLD amounts (in wei, 18 decimals) matching recipients
     * @param note Quarter label e.g. "Q1 2026"
     */
    function distribute(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string calldata note
    ) external onlyOwner {
        require(recipients.length > 0, "No recipients");
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length <= 500, "Too many recipients");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Zero amount");
            require(recipients[i] != address(0), "Zero address recipient");
            totalAmount += amounts[i];
        }

        // Pull total from owner wallet in one transferFrom
        require(
            mtyld.transferFrom(msg.sender, address(this), totalAmount),
            "TransferFrom failed - approve contract first"
        );

        uint256 distributionId = distributions.length;

        // Push to each recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            require(mtyld.transfer(recipients[i], amounts[i]), "Transfer failed");
            totalReceived[recipients[i]] += amounts[i];
            emit RecipientPaid(distributionId, recipients[i], amounts[i]);
        }

        distributions.push(Distribution({
            timestamp: block.timestamp,
            totalAmount: totalAmount,
            recipientCount: recipients.length,
            note: note
        }));

        emit DistributionExecuted(
            distributionId,
            totalAmount,
            recipients.length,
            note,
            block.timestamp
        );
    }

    /**
     * @notice Distribute proportionally by weight.
     * @dev Useful when you know percentages but not exact amounts.
     * @param recipients Array of employee wallet addresses  
     * @param weights Relative weights (e.g. [50, 30, 20] for 50%/30%/20%)
     * @param totalAmount Total MTYLD to distribute (in wei)
     * @param note Quarter label
     */
    function distributeProportional(
        address[] calldata recipients,
        uint256[] calldata weights,
        uint256 totalAmount,
        string calldata note
    ) external onlyOwner {
        require(recipients.length > 0, "No recipients");
        require(recipients.length == weights.length, "Length mismatch");
        require(totalAmount > 0, "Zero amount");
        require(recipients.length <= 500, "Too many recipients");

        // Calculate total weight
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            require(weights[i] > 0, "Zero weight");
            require(recipients[i] != address(0), "Zero address");
            totalWeight += weights[i];
        }

        // Pull total from owner
        require(
            mtyld.transferFrom(msg.sender, address(this), totalAmount),
            "TransferFrom failed - approve contract first"
        );

        uint256 distributionId = distributions.length;
        uint256 distributed = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 amount;
            // Give remainder to last recipient to avoid dust
            if (i == recipients.length - 1) {
                amount = totalAmount - distributed;
            } else {
                amount = (totalAmount * weights[i]) / totalWeight;
            }

            if (amount > 0) {
                require(mtyld.transfer(recipients[i], amount), "Transfer failed");
                totalReceived[recipients[i]] += amount;
                distributed += amount;
                emit RecipientPaid(distributionId, recipients[i], amount);
            }
        }

        distributions.push(Distribution({
            timestamp: block.timestamp,
            totalAmount: totalAmount,
            recipientCount: recipients.length,
            note: note
        }));

        emit DistributionExecuted(
            distributionId,
            totalAmount,
            recipients.length,
            note,
            block.timestamp
        );
    }

    // ── View functions ────────────────────────────────────────

    /// @notice Total number of distributions ever executed
    function distributionCount() external view returns (uint256) {
        return distributions.length;
    }

    /// @notice Get details of a specific distribution
    function getDistribution(uint256 id) external view returns (
        uint256 timestamp,
        uint256 totalAmount,
        uint256 recipientCount,
        string memory note
    ) {
        require(id < distributions.length, "Invalid id");
        Distribution memory d = distributions[id];
        return (d.timestamp, d.totalAmount, d.recipientCount, d.note);
    }

    /// @notice Get all distributions
    function getAllDistributions() external view returns (Distribution[] memory) {
        return distributions;
    }

    /// @notice MTYLD balance sitting in this contract (should be 0 after distribution)
    function contractBalance() external view returns (uint256) {
        return mtyld.balanceOf(address(this));
    }

    // ── Emergency ─────────────────────────────────────────────

    /// @notice Recover any stuck tokens (safety valve)
    function recoverTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
        emit TokensRecovered(token, amount);
    }
}
