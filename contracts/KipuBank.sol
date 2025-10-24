//SPDX-License-Identifier: MIT

pragma solidity   > 0.8.26;

/**
 * @title KipuBank Contract
 * @notice Educational-only contract. Do not use in production.
 * @author JuanMoisio
 * @custom:security Not for production use.
 */
contract KipuBank {

    /*///////////////////////
                        Variables
    ///////////////////////*/
    
    /// @notice Mapping that stores each client's balance in wei.
    mapping(address client => uint256 amount) public balances;
    
    /// @notice Immutable per-withdrawal maximum (in wei).
    uint256 public immutable WITHDRAW_MAX;

    /// @notice Immutable global cap of total allowed transactions (deposits).
    uint256 public  immutable bankCap;

    /// @notice Global counter of successful deposit transactions.
    uint256 public transactionsCounter;

    /// @notice Global counter of successful withdrawals.
    uint256 public withdrawalCounter;


	 /*///////////////////////
                        Events
    ////////////////////////*/
    /// @notice Emitted when a new deposit is completed.
    /// @param client Address that deposited.
    /// @param amount Amount deposited in wei.
    event depositDone(address client, uint256 amount);
	
    /// @notice Emitted when a withdrawal is completed.
    /// @param client Address that withdrew.
    /// @param amount Amount withdrawn in wei.
    event withdrawalDone(address client, uint256 amount);
	
	/*///////////////////////
						Errors
	///////////////////////*/

	/// @notice Thrown when a low-level ETH transfer fails.
    error transactionFailed();

    /// @notice Thrown when attempting to withdraw more than the available balance.
    /// @param have Current available balance.
    /// @param need Requested amount.
    error insufficientBalance(uint256 have, uint256 need);

    /// @notice Thrown when requested amount exceeds the per-withdrawal cap.
    /// @param requested Requested amount.
    /// @param cap Current configured cap.
    error capExceeded(uint256 requested, uint256 cap);

	/// @notice Thrown when an address different than the beneficiary tries to withdraw (not used in this version).
    /// @param thief Caller address.
    /// @param victim Intended beneficiary.
    error wrongUser(address thief, address victim);

    /// @notice Thrown when the global transactions limit is reached or exceeded.
    /// @param transactions Current number of transactions.
    /// @param limit Global transactions limit.
    error maxTransactionsLimit(uint256 transactions, uint256 limit);

     /// @notice Thrown when trying to deposit 0 wei.
    error zeroDeposit();

    /// @notice Thrown when deploying with a WITHDRAW_MAX less than or equal to zero (educational message).
    error noCapWei();

    /// @notice Thrown when deploying with a bankCap less than or equal to zero (educational message).
    error noTransactions();

    /// @notice Thrown on reentrancy attempts.
    error reentrancy();

    /**
     * @notice Initializes the contract with the per-withdrawal cap and the global transactions limit.
     * @dev Educational checks kept as provided by the author.
     * @param capWei Per-withdrawal maximum (wei).
     * @param maxTransactions Global maximum number of transactions (deposits).
     */
    constructor(uint256 capWei, uint256 maxTransactions) {
        if(capWei < 0) revert noCapWei();
        WITHDRAW_MAX = capWei; 
        if(maxTransactions < 0) revert noTransactions();
        bankCap = maxTransactions;
    }

        /*///////////////////////
            Modifiers
    ///////////////////////*/
    
    /// @dev Prevents zero-wei deposits.
    modifier nonZeroValue() {
        if (msg.value == 0) revert zeroDeposit();
        _;
    }

    /// @dev Ensures the global transactions counter has not reached the bank cap.
    modifier underTxCap() {
        if (transactionsCounter >= bankCap) {
            revert maxTransactionsLimit(transactionsCounter, bankCap);
        }
        _;
    }

     /// @dev Post-action: increments the deposit counter after function body executes successfully.
    modifier countDeposit() {
        _;
        transactionsCounter += 1;
    }
    
    uint256 private _locked; // 0 = free, 1 = locked

    /// @dev Simple non-reentrancy guard.
    modifier nonReentrant() {
        if (_locked == 1) revert reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    /// @dev Post-action: increments the withdrawal counter after function body executes successfully.
    modifier countWithdrawal() {
        _;
        withdrawalCounter += 1;
    }

     /**
     * @dev Ensures the caller has enough balance to cover `amount`.
     * @param amount Amount required (wei).
     */
    modifier hasFunds(uint256 amount) {
        uint256 bal = balances[msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);
        _;
    }
    /**
     * @dev Ensures the withdrawal `amount` does not exceed the configured per-withdrawal cap.
     * @param amount Amount to withdraw (wei).
     */
    modifier withinWithdrawCap(uint256 amount) {
        if (amount > WITHDRAW_MAX) revert capExceeded(amount, WITHDRAW_MAX);
        _;
    }




    /*///////////////////////
					Functions
	///////////////////*/

    
    
    /**
     * @notice Deposits the sent ETH (`msg.value`) into the caller's balance.
     * @dev Order of execution: PRE (nonZeroValue, underTxCap) → BODY → POST (countDeposit).
     *      Emits {depositDone}.
     */
    function deposit() external payable nonZeroValue underTxCap countDeposit{
        balances[msg.sender] += msg.value;
        emit depositDone(msg.sender, msg.value);
    }


    /**
     * @notice Withdraws `value` wei from the caller's balance and transfers it to the caller.
     * @dev Order of execution: PRE (withinWithdrawCap, hasFunds, nonReentrant) → BODY → POST (countWithdrawal).
     *      Uses a low-level call and reverts on failure. Emits {withdrawalDone}.
     * @param value Amount to withdraw in wei.
     */
    function withdrawal(uint256 value) external  nonReentrant withinWithdrawCap(value) hasFunds(value) countWithdrawal{
        _debit(msg.sender, value);
        (bool ok, ) = msg.sender.call{value: value}("");
        if(!ok)revert transactionFailed();
        emit withdrawalDone(msg.sender,value);
    }


    /**
     * @notice Returns global counters for deposits and withdrawals.
     * @return totalDeposits Number of successful deposits.
     * @return totalwithdrawal Number of successful withdrawals.
     */
    function bankStats()external view returns ( uint256 totalDeposits, uint256 totalwithdrawal) {
        totalDeposits = transactionsCounter;
        totalwithdrawal = withdrawalCounter;
    }


    /**
     * @dev Internal helper that debits `amount` from `user`'s balance.
     * @param user Address whose balance will be debited.
     * @param amount Amount to debit (wei).
     */
    function _debit(address user, uint256 amount) private {
        uint256 bal = balances[user];             
        if (amount > bal) revert insufficientBalance(bal, amount);
        unchecked { balances[user] = bal - amount; } 
    }
}