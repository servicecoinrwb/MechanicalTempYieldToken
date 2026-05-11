// SPDX-License-Identifier: MIT
/**
 * CompoundStrategy — Compound V3 WETH yield strategy
 *
 * Implements IStrategy. Pulls WETH from vault via transferFrom,
 * supplies to Compound V3, withdraws back to vault on demand.
 *
 * Deploy: CompoundStrategy(vaultAddress)
 * Then:   vault.approveToken(WETH, address(this), type(uint256).max)
 *         vault.addStrategy(address(this), "Compound V3")
 */

pragma solidity ^0.8.25;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IComet {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IConservatorVault {
    function owner() external view returns (address);
    function aiAgent() external view returns (address);
}

abstract contract Ownable {
    address private _owner;
    constructor(address o) { _owner = o; }
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    function owner() public view returns (address) { return _owner; }
}

contract CompoundStrategy is Ownable {

    // ── Arbitrum One addresses ────────────────────────────────
    address public constant COMPOUND = 0x6f7D514bbD4aFf3BcD1140B7344b32f063dEe486;
    address public constant WETH     = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public immutable vault_;

    constructor(address _vault) Ownable(msg.sender) {
        require(_vault != address(0), "Zero vault");
        vault_ = _vault;
        // Approve Compound to spend WETH held by this strategy
        IERC20(WETH).approve(COMPOUND, type(uint256).max);
    }

    modifier onlyAuthorized() {
        IConservatorVault v = IConservatorVault(vault_);
        require(
            msg.sender == vault_      ||
            msg.sender == v.aiAgent() ||
            msg.sender == v.owner()   ||
            msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    // ── IStrategy implementation ──────────────────────────────

    function name() external pure returns (string memory) {
        return "Compound V3";
    }

    function vault() external view returns (address) {
        return vault_;
    }

    /// @notice Pull WETH from vault and supply to Compound
    function deposit(uint256 amount) external onlyAuthorized {
        require(amount > 0, "Zero amount");
        // Pull WETH from vault (vault has approved this contract)
        IERC20(WETH).transferFrom(vault_, address(this), amount);
        // Supply to Compound
        IComet(COMPOUND).supply(WETH, amount);
    }

    /// @notice Withdraw WETH from Compound and send back to vault
    function withdraw(uint256 amount) external onlyAuthorized {
        require(amount > 0, "Zero amount");
        IComet(COMPOUND).withdraw(WETH, amount);
        IERC20(WETH).transfer(vault_, IERC20(WETH).balanceOf(address(this)));
    }

    /// @notice Withdraw everything from Compound back to vault
    function withdrawAll() external onlyAuthorized {
        uint256 bal = IComet(COMPOUND).balanceOf(address(this));
        if (bal == 0) return;
        IComet(COMPOUND).withdraw(WETH, bal);
        uint256 wethBal = IERC20(WETH).balanceOf(address(this));
        if (wethBal > 0) IERC20(WETH).transfer(vault_, wethBal);
    }

    /// @notice Current WETH value in Compound (includes accrued yield)
    function balance() external view returns (uint256) {
        return IComet(COMPOUND).balanceOf(address(this));
    }

    // ── Emergency ─────────────────────────────────────────────

    function emergencyRecover(address token, address to) external onlyOwner {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "Nothing to recover");
        IERC20(token).transfer(to, bal);
    }
}
