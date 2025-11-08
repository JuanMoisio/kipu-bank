// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBank
 * @notice Educational-only contract. Do not use in production.
 * @author JuanMoisio
 */
contract KipuBank is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice ETH balances per user (wei).
    mapping(address => uint256) public balances;

    /// @notice Per-withdrawal cap for ETH (wei).
    uint256 public immutable WITHDRAW_MAX;

    /// @notice Global cap for successful deposit transactions.
    uint256 public immutable bankCap;

    /// @notice Successful deposits counter.
    uint256 public transactionsCounter;

    /// @notice Successful withdrawals counter.
    uint256 public withdrawalCounter;

    /// @notice Bank USD cap with 8 decimals (0 disables).
    uint256 public immutable bankUsdCap;

    /// @notice Outstanding ETH liabilities valued in USD(8).
    uint256 public bankUsdLiabilities;

    /// @notice Chainlink ETH/USD price feed (8 decimals).
    AggregatorV3Interface public immutable ethUsdFeed;

    /// @notice Chainlink XAU/USD price feed (8 decimals).
    AggregatorV3Interface public immutable xauUsdFeed;

    /// @notice Maximum oracle staleness allowed.
    uint256 public maxOracleDelay = 1 hours;

    /// @notice ERC-20 balances per token and user.
    mapping(IERC20 => mapping(address => uint256)) public erc20Balances;

    /// @notice Official ERC-20 accepted by the bank (KGLD).
    IERC20 public immutable KGLD;

    /// @notice Per-withdrawal cap for KGLD in token units (0 disables).
    uint256 public immutable WITHDRAW_MAX_KGLD;

    /// @notice Emitted when an ETH deposit is completed.
    event depositDone(address indexed client, uint256 amountWei);

    /// @notice Emitted when an ETH withdrawal is completed.
    event withdrawalDone(address indexed client, uint256 amountWei);

    /// @notice Emitted when an ERC-20 deposit is completed.
    event erc20DepositDone(address indexed token, address indexed client, uint256 amount);

    /// @notice Emitted when an ERC-20 withdrawal is completed.
    event erc20WithdrawalDone(address indexed token, address indexed client, uint256 amount);

    /// @notice Emitted when the max oracle delay is updated.
    event MaxOracleDelayUpdated(uint256 newDelay);

    /// @notice Emitted when swapping ETH for KGLD.
    event SwapEthForKGLD(address indexed user, uint256 weiIn, uint256 kglOut);

    /// @notice Emitted when swapping KGLD for ETH.
    event SwapKGLDForEth(address indexed user, uint256 kglIn, uint256 weiOut);

    /// @notice Thrown when a low-level ETH transfer via call fails.
    error transactionFailed();

    /// @notice Thrown when the caller tries to use more funds than available.
    /// @param have Current available balance.
    /// @param need Requested amount.
    error insufficientBalance(uint256 have, uint256 need);

    /// @notice Thrown when a requested amount exceeds the configured per-withdrawal cap.
    /// @param requested Amount requested by the caller.
    /// @param cap Current per-withdrawal cap.
    error capExceeded(uint256 requested, uint256 cap);

    /// @notice Thrown when the global successful-deposit counter would exceed the bank cap.
    /// @param transactions Current number of successful deposits.
    /// @param limit Global cap of successful deposits.
    error maxTransactionsLimit(uint256 transactions, uint256 limit);

    /// @notice Thrown when attempting to deposit zero amount (ETH or tokens).
    error zeroDeposit();

    /// @notice Thrown when deploying with an ETH withdraw cap of zero.
    error noCapWei();

    /// @notice Thrown when deploying with a deposits cap of zero.
    error noTransactions();

    /// @notice Thrown on reentrancy attempts detected by the lock guard.
    error reentrancy();

    /// @notice Thrown when a Chainlink price feed returns an invalid or stale value.
    error invalidPrice();

    /// @notice Thrown when adding an ETH deposit would exceed the configured USD liabilities cap.
    /// @param newLiability Liabilities after the attempted operation (USD, 8 decimals).
    /// @param cap Configured liabilities cap (USD, 8 decimals).
    error bankUsdCapExceeded(uint256 newLiability, uint256 cap);

    /// @notice Thrown when an unexpected ERC-20 token is provided where KGLD is required.
    /// @param provided Address of the token provided.
    /// @param expected Address of the required token (KGLD).
    error wrongToken(address provided, address expected);

    /// @notice Thrown when a KGLD withdrawal exceeds the token's per-withdrawal cap.
    /// @param requested KGLD amount requested.
    /// @param cap Per-withdrawal KGLD cap.
    error capExceededKGLD(uint256 requested, uint256 cap);

    /// @notice Thrown when a swap/deposit/withdraw is invoked with a zero amount.
    error ZeroAmount();

    /// @notice Thrown when the contract lacks sufficient ETH or KGLD to fulfill a swap/withdrawal.
    error InsufficientLiquidity();


    /**
     * @notice Initializes the bank.
     * @param initialOwner Owner address.
     * @param capWei Per-withdrawal ETH cap (wei).
     * @param maxTransactions Global cap of successful deposits.
     * @param ethUsdPriceFeed Chainlink ETH/USD feed (8 decimals).
     * @param bankUsdCap_ USD(8) liabilities cap for ETH (0 disables).
     * @param kgldToken Official ERC-20 token (KGLD).
     * @param capKGLD Per-withdrawal cap for KGLD (0 disables).
     * @param xauUsdPriceFeed Chainlink XAU/USD feed (8 decimals).
     */
    constructor(
        address initialOwner,
        uint256 capWei,
        uint256 maxTransactions,
        AggregatorV3Interface ethUsdPriceFeed,
        uint256 bankUsdCap_,
        IERC20 kgldToken,
        uint256 capKGLD,
        AggregatorV3Interface xauUsdPriceFeed
    ) Ownable(initialOwner) {
        if (capWei == 0) revert noCapWei();
        if (maxTransactions == 0) revert noTransactions();

        WITHDRAW_MAX      = capWei;
        bankCap           = maxTransactions;
        ethUsdFeed        = ethUsdPriceFeed;
        bankUsdCap        = bankUsdCap_;
        KGLD              = kgldToken;
        WITHDRAW_MAX_KGLD = capKGLD;
        xauUsdFeed        = xauUsdPriceFeed;
    }

    /**
     * @notice Accepts plain ETH to fund swap liquidity.
     */
    receive() external payable {}

    uint256 private _locked;

    /**
     * @dev Simple non-reentrancy guard.
     */
    modifier nonReentrant() {
        if (_locked == 1) revert reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    /**
     * @dev Validates per-withdrawal cap for ETH.
     * @param amount Amount to withdraw.
     */
    modifier withinWithdrawCap(uint256 amount) {
        if (amount > WITHDRAW_MAX) revert capExceeded(amount, WITHDRAW_MAX);
        _;
    }

    /**
     * @dev Validates per-withdrawal cap for KGLD (0 disables).
     * @param amount Amount to withdraw.
     */
    modifier withinWithdrawCapKGLD(uint256 amount) {
        if (WITHDRAW_MAX_KGLD != 0 && amount > WITHDRAW_MAX_KGLD) {
            revert capExceededKGLD(amount, WITHDRAW_MAX_KGLD);
        }
        _;
    }

    /**
     * @notice Updates maximum oracle delay.
     * @param newDelay New delay in seconds.
     */
    function setMaxOracleDelay(uint256 newDelay) external onlyOwner {
        maxOracleDelay = newDelay;
        emit MaxOracleDelayUpdated(newDelay);
    }

    /**
     * @notice Reads a fresh price from a Chainlink feed with staleness checks.
     * @param feed AggregatorV3Interface feed.
     * @return price Latest price with 8 decimals.
     */
    function _freshPrice(AggregatorV3Interface feed) internal view returns (uint256 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        if (answer <= 0) revert invalidPrice();
        if (answeredInRound < roundId) revert invalidPrice();
        if (block.timestamp - updatedAt > maxOracleDelay) revert invalidPrice();
        price = uint256(answer);
    }

    /**
     * @notice Returns latest ETH/USD price (8 decimals).
     */
    function _getEthUsdPrice() internal view returns (uint256) {
        return _freshPrice(ethUsdFeed);
    }

    /**
     * @notice Returns latest XAU/USD price (8 decimals).
     */
    function _getXauUsdPrice() internal view returns (uint256) {
        return _freshPrice(xauUsdFeed);
    }

    /**
     * @notice Converts wei to USD(8 decimals) using Chainlink.
     * @param weiAmount ETH amount in wei.
     * @return usdAmount USD with 8 decimals.
     */
    function _weiToUsd(uint256 weiAmount) internal view returns (uint256 usdAmount) {
        uint256 ethUsd = _getEthUsdPrice();
        usdAmount = (weiAmount * ethUsd) / 1e18;
    }

    /**
     * @notice Deposits ETH into caller's internal balance.
     */
    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert zeroDeposit();

        uint256 _txs = transactionsCounter;
        uint256 _cap = bankCap;
        uint256 next = _txs + 1;
        if (next > _cap) revert maxTransactionsLimit(_txs, _cap);

        uint256 addUsd = _weiToUsd(msg.value);
        uint256 _bankUsdCap = bankUsdCap;
        uint256 _usdLiabilities = bankUsdLiabilities;

        if (_bankUsdCap != 0) {
            uint256 newLiability = _usdLiabilities + addUsd;
            if (newLiability > _bankUsdCap) revert bankUsdCapExceeded(newLiability, _bankUsdCap);
            bankUsdLiabilities = newLiability;
        } else {
            unchecked { bankUsdLiabilities = _usdLiabilities + addUsd; }
        }

        unchecked { balances[msg.sender] += msg.value; }
        transactionsCounter = next;

        emit depositDone(msg.sender, msg.value);
    }

    /**
     * @notice Withdraws ETH from caller's internal balance.
     * @param amount Amount in wei.
     */
    function withdrawal(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        withinWithdrawCap(amount)
    {
        uint256 bal = balances[msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);

        unchecked { balances[msg.sender] = bal - amount; }

        uint256 subUsd = _weiToUsd(amount);
        uint256 _usdLiabilities = bankUsdLiabilities;
        uint256 newLiab = subUsd > _usdLiabilities ? 0 : _usdLiabilities - subUsd;
        bankUsdLiabilities = newLiab;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert transactionFailed();

        unchecked { withdrawalCounter += 1; }
        emit withdrawalDone(msg.sender, amount);
    }

    /**
     * @notice Returns global counters.
     * @return totalDeposits Deposits counter.
     * @return totalWithdrawals Withdrawals counter.
     */
    function bankStats() external view returns (uint256 totalDeposits, uint256 totalWithdrawals) {
        return (transactionsCounter, withdrawalCounter);
    }

    /**
     * @notice Deposits KGLD into caller's internal balance.
     * @param amount Token units.
     */
    function depositKGLD(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert zeroDeposit();

        uint256 _txs = transactionsCounter;
        uint256 _cap = bankCap;
        uint256 next = _txs + 1;
        if (next > _cap) revert maxTransactionsLimit(_txs, _cap);

        KGLD.safeTransferFrom(msg.sender, address(this), amount);
        unchecked { erc20Balances[KGLD][msg.sender] += amount; }

        transactionsCounter = next;
        emit erc20DepositDone(address(KGLD), msg.sender, amount);
    }

    /**
     * @notice Withdraws KGLD to caller.
     * @param amount Token units.
     */
    function withdrawKGLD(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        withinWithdrawCapKGLD(amount)
    {
        uint256 bal = erc20Balances[KGLD][msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);

        unchecked { erc20Balances[KGLD][msg.sender] = bal - amount; }
        KGLD.safeTransfer(msg.sender, amount);

        unchecked { withdrawalCounter += 1; }
        emit erc20WithdrawalDone(address(KGLD), msg.sender, amount);
    }

    /**
     * @notice Swaps ETH for KGLD at gold (XAU) price.
     * @return outKGLD KGLD amount sent to caller.
     */
    function swapEthForKGLD()
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 outKGLD)
    {
        uint256 weiIn = msg.value;
        if (weiIn == 0) revert ZeroAmount();

        uint256 ethUsd = _getEthUsdPrice();
        uint256 xauUsd = _getXauUsdPrice();

        outKGLD = (weiIn * ethUsd * 1_000_000) / xauUsd;

        uint256 kglBal = KGLD.balanceOf(address(this));
        if (outKGLD > kglBal) revert InsufficientLiquidity();

        KGLD.safeTransfer(msg.sender, outKGLD);
        emit SwapEthForKGLD(msg.sender, weiIn, outKGLD);
    }

    /**
     * @notice Swaps KGLD (requires allowance) for ETH at gold (XAU) price.
     * @param amountKGLD KGLD amount to swap.
     * @return outWei ETH amount sent to caller.
     */
    function swapKGLDForEth(uint256 amountKGLD)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 outWei)
    {
        if (amountKGLD == 0) revert ZeroAmount();

        uint256 ethUsd = _getEthUsdPrice();
        uint256 xauUsd = _getXauUsdPrice();

        outWei = (amountKGLD * xauUsd) / (ethUsd * 1_000_000);
        if (outWei > address(this).balance) revert InsufficientLiquidity();

        KGLD.safeTransferFrom(msg.sender, address(this), amountKGLD);

        (bool ok,) = payable(msg.sender).call{value: outWei}("");
        if (!ok) revert transactionFailed();

        emit SwapKGLDForEth(msg.sender, amountKGLD, outWei);
    }

    /**
     * @notice Pauses state-changing functions.
     */
    function pause() external onlyOwner { _pause(); }

    /**
     * @notice Unpauses state-changing functions.
     */
    function unpause() external onlyOwner { _unpause(); }
}
