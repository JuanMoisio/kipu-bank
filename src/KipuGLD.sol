// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

    /**
    * @title Kipu Gold (KGLD)
    * @notice Educational ERC-20 with burn, pause and EIP-2612 permit.
    * @dev Uses OpenZeppelin v5. Default decimals: 18.
    */
    contract KipuGLD is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, Ownable {
    /**
     * @notice Deploys the token and mints the initial supply to the owner.
     * @param initialOwner Contract owner.
     * @param initialSupply Initial supply in token units (18 decimals).
     */
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("Kipu Gold", "KGLD")
        ERC20Permit("Kipu Gold")
        Ownable(initialOwner)
    {
        _mint(initialOwner, initialSupply);
    }

    /// @notice Pause token transfers.
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause token transfers.
    function unpause() external onlyOwner { _unpause(); }

    /**
     * @notice Mint new tokens.
     * @param to Recipient address.
     * @param amount Amount in token units.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @dev Required in OZ v5 to resolve the inheritance diamond with ERC20Pausable.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
