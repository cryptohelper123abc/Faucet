// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.6;


import "./SafeMath.sol";
import "./Context.sol";     
import "./IERC20.sol";      // Need this to withdraw certain tokens
import "./SafeERC20.sol";   // withdraw airdropped token




/*

HOW TO USE THE FAUCET SYSTEM




01. Send the Token to the Faucet Contract
02. Have the director of the faucet contract either initialize you as manager or the director can initialize the faucet himself.
03. Initialize Fuacet for Token - input address, amount (with decimals of token), and cooldown time (in second unix time)
04. Make sure that the Faucet Contract is excluded from Taxes and Transfer Restrictions
04. Enable Faucet








*/


contract Faucet is Context {







    //////////////////////////// USING STATEMENTS ////////////////////////////
    using SafeMath for uint256;
    using SafeERC20 for IERC20; // this is for IERC20 tokens that you can store in the airdrop contract
    //////////////////////////// USING STATEMENTS ////////////////////////////








    //////////////////////////// AIRDROP CONTRACT INFO VARS ////////////////////////////
    uint256 public releaseDateUnixTimeStamp = block.timestamp;     // Version 2 Release Date
    //////////////////////////// AIRDROP CONTRACT INFO VARS ////////////////////////////








    //////////////////////////// DEAD ADDRESSES ////////////////////////////
    address public deadAddressZero = 0x0000000000000000000000000000000000000000; 
    address public deadAddressOne = 0x0000000000000000000000000000000000000001; 
    address public deadAddressdEaD = 0x000000000000000000000000000000000000dEaD; 
    //////////////////////////// DEAD ADDRESSES ////////////////////////////











    //////////////////////////// ACCESS CONTROL VARS ////////////////////////////
    address public directorAccount = 0x8C7Ad6F014B46549875deAD0f69919d643a50bA3;      // CHANGEIT - get the right director account

    // This will keep track of who is the manager of a token. 
    // Managers can initialize faucets for a specific address
    mapping(address => address) public tokenAddressToManagerAddress;       
    //////////////////////////// ACCESS CONTROL VARS ////////////////////////////













    
    //////////////////////////// FAUCET VARS ////////////////////////////  
    mapping(address => bool) public isFaucetEnabled;    
    mapping(address => uint256) public amountToGiveForAddress;    
    mapping(address => uint256) public cooldownTimeForAddress;   
    mapping(address => bool) public isClaiming;     // reentrancy guard
    mapping(address => mapping(address => uint256)) public tokenAddressToUserAddressToClaimTime;    // when has the user claimed from the faucet, last - if 0, has not claimed
    //////////////////////////// FAUCET VARS ////////////////////////////  


















    //////////////////////////// EVENTS ////////////////////////////
    event InitilizationOfFaucet(address indexed tokenAddress, address indexed initializerAddress, uint256 currentBlockTime);
    event FaucetEnabled(address indexed tokenAddress, address indexed initializerAddress, uint256 currentBlockTime);
    event FaucetDisabled(address indexed tokenAddress, address indexed initializerAddress, uint256 currentBlockTime);
    event FaucetUsed(address indexed tokenAddress, address indexed claimer, uint256 amountGiven, uint256 currentBlockTime);

    event TransferedDirectorAccount(address indexed oldDirectorAccount, address indexed newDirectorAccount, uint256 currentBlockTime);
    event ManagerInitialized(address indexed tokenAddress, address indexed managerAddress, uint256 currentBlockTime);

    event ETHwithdrawnRecovered(address indexed claimerWalletOwner, uint256 indexed ethClaimedRecovered, uint256 currentBlockTime);
    event ERC20tokenWithdrawnRecovered(address indexed tokenAddress, address indexed claimerWalletOwner, uint256 indexed balanceClaimedRecovered, uint256 currentBlockTime);
    //////////////////////////// EVENTS ////////////////////////////




















    //////////////////////////// ACCESS CONTROL MODIFIERS ////////////////////////////
    modifier OnlyDirector() {
        require(directorAccount == _msgSender(), "Caller must be the Director");
        _;
    }

    modifier OnlyStaff(address tokenAddress) {
        address managerAddress = tokenAddressToManagerAddress[tokenAddress];
        require(managerAddress == _msgSender() || directorAccount == _msgSender(), "Caller must be Director or Manager");
        _;
    }
    //////////////////////////// ACCESS CONTROL MODIFIERS ////////////////////////////










    //////////////////////////// ACCESS CONTROL FUNCTIONS ////////////////////////////
    function TransferDirectorAccount(address newDirectorAccount) public virtual OnlyDirector() {
        address oldDirectorAccount = directorAccount;
        directorAccount = newDirectorAccount;
        emit TransferedDirectorAccount(oldDirectorAccount, newDirectorAccount, GetCurrentBlockTime());
    }

    function InitializeManagerForToken(address tokenAddress, address managerAddress) external OnlyDirector() { 
        tokenAddressToManagerAddress[tokenAddress] = managerAddress;
        emit ManagerInitialized(tokenAddress, managerAddress, GetCurrentBlockTime());
    }
    //////////////////////////// ACCESS CONTROL FUNCTIONS ////////////////////////////













    //////////////////////////// FAUCET FUNCTIONS ////////////////////////////  
    function InitializeFaucetForToken(address tokenAddress, uint256 amountToGivePerClaim, uint256 cooldownTimeBetweenClaims) external OnlyStaff(tokenAddress) { 

        // amount to give is including the decimal spaces
        require(amountToGivePerClaim > 0, "Amount to give per claim must be greater than 0");
        amountToGiveForAddress[tokenAddress] = amountToGivePerClaim;

        // if cooldownTime is set to 0 then there it is assumed that each address can only claim once.
        cooldownTimeForAddress[tokenAddress] = cooldownTimeBetweenClaims;

        emit InitilizationOfFaucet(tokenAddress, _msgSender(), GetCurrentBlockTime());
    }

    function EnableFaucet(address tokenAddress) public OnlyStaff(tokenAddress) {
        isFaucetEnabled[tokenAddress] = true;
        emit FaucetEnabled(tokenAddress, _msgSender(), GetCurrentBlockTime());
    }

    function DisableFaucet(address tokenAddress) public OnlyStaff(tokenAddress) {
        isFaucetEnabled[tokenAddress] = false;
        emit FaucetDisabled(tokenAddress, _msgSender(), GetCurrentBlockTime());
    }



    function FaucetClaim(address tokenAddress) public {    

        address claimer = _msgSender();

        require(!isClaiming[claimer], "Claim one at a time");
        isClaiming[claimer] = true;

        require(isFaucetEnabled[tokenAddress], "Faucet must be enabled. It is currently disabled. Contact the Director or the Manager of this Token.");  


        uint256 lastClaimTime = tokenAddressToUserAddressToClaimTime[tokenAddress][claimer];
        tokenAddressToUserAddressToClaimTime[tokenAddress][claimer] = GetCurrentBlockTime();        // set for reetrancy

        uint256 amountoToGive = amountToGiveForAddress[tokenAddress];

        uint256 cooldownTime = cooldownTimeForAddress[tokenAddress];

        if(cooldownTime != 0){
            require(GetCurrentBlockTime() > lastClaimTime.add(cooldownTime), "You must wait until the cooldown finishes to get more of the token.");
        }
        else{   // if the cool down time is zero, the the user can only claim once
            require(lastClaimTime == 0, "You can only claim this token once.");
        }

        // There needs to be enough token in the contract for the faucet to give
        require(CurrentFaucetTokenSupplyInContract(IERC20(tokenAddress)) >= amountoToGive,"Not enough Airdrop Token in Contract");   

        IERC20(tokenAddress).safeTransfer(PayableInputAddress(claimer), amountoToGive);

        emit FaucetUsed(tokenAddress, claimer, amountoToGive, GetCurrentBlockTime());

        isClaiming[claimer] = false;

    }

    function CurrentFaucetTokenSupplyInContract(IERC20 tokenAddress) public view returns (uint256) {
        return tokenAddress.balanceOf(address(this));
    }



    function isFaucetUsable(address tokenAddress, address userAddress) public view returns (bool) {

        uint256 cooldownTime = cooldownTimeForAddress[tokenAddress];
        uint256 lastClaimTime = tokenAddressToUserAddressToClaimTime[tokenAddress][userAddress];

        if(cooldownTime != 0){
            if(GetCurrentBlockTime() > lastClaimTime.add(cooldownTime)){
                return true;
            }
        }
        else{   // if the cool down time is zero, the the user can only claim once
            if(lastClaimTime == 0){
                return true;
            }
        }
        return false;
    }
    //////////////////////////// FAUCET FUNCTIONS ////////////////////////////  









































    //////////////////////////// RESCUE FUNCTIONS ////////////////////////////
    function RescueAllETHSentToContractAddress() external OnlyDirector()  {   
        uint256 balanceOfContract = address(this).balance;
        PayableInputAddress(directorAccount).transfer(balanceOfContract);
        emit ETHwithdrawnRecovered(directorAccount, balanceOfContract, GetCurrentBlockTime());
    }

    function RescueAmountETHSentToContractAddress(uint256 amountToRescue) external OnlyDirector()  {   
        PayableInputAddress(directorAccount).transfer(amountToRescue);
        emit ETHwithdrawnRecovered(directorAccount, amountToRescue, GetCurrentBlockTime());
    }

    function RescueAllTokenSentToContractAddressAsDirector(IERC20 tokenToWithdraw) external OnlyDirector() {
        uint256 balanceOfContract = tokenToWithdraw.balanceOf(address(this));
        tokenToWithdraw.safeTransfer(PayableInputAddress(directorAccount), balanceOfContract);
        emit ERC20tokenWithdrawnRecovered(address(tokenToWithdraw), directorAccount, balanceOfContract, GetCurrentBlockTime());
    }

    function RescueAmountTokenSentToContractAddressAsDirector(IERC20 tokenToWithdraw, uint256 amountToRescue) external OnlyDirector() {
        tokenToWithdraw.safeTransfer(PayableInputAddress(directorAccount), amountToRescue);
        emit ERC20tokenWithdrawnRecovered(address(tokenToWithdraw), directorAccount, amountToRescue, GetCurrentBlockTime());
    }

    function RescueAllTokenSentToContractAddressAsManager(IERC20 tokenToWithdraw) external OnlyStaff(address(tokenToWithdraw)) {
        address tokenAddress = address(tokenToWithdraw);
        address managerOfToken = tokenAddressToManagerAddress[tokenAddress];
        uint256 balanceOfContract = tokenToWithdraw.balanceOf(address(this));
        tokenToWithdraw.safeTransfer(PayableInputAddress(directorAccount), balanceOfContract);
        emit ERC20tokenWithdrawnRecovered(address(tokenToWithdraw), managerOfToken, balanceOfContract, GetCurrentBlockTime());
    }

    function RescueAmountTokenSentToContractAddressAsManager(IERC20 tokenToWithdraw, uint256 amountToRescue) external OnlyStaff(address(tokenToWithdraw)) {
        address tokenAddress = address(tokenToWithdraw);
        address managerOfToken = tokenAddressToManagerAddress[tokenAddress];
        tokenToWithdraw.safeTransfer(PayableInputAddress(directorAccount), amountToRescue);
        emit ERC20tokenWithdrawnRecovered(address(tokenToWithdraw), managerOfToken, amountToRescue, GetCurrentBlockTime());
    }
    //////////////////////////// RESCUE FUNCTIONS ////////////////////////////






















    //////////////////////////// MISC INFO FUNCTIONS ////////////////////////////  
    function PayableInputAddress(address inputAddress) internal pure returns (address payable) {   // gets the sender of the payable address
        address payable payableInAddress = payable(address(inputAddress));
        return payableInAddress;
    }

    function GetCurrentBlockTime() public view returns (uint256) {
        return block.timestamp;     // gets the current time and date in Unix timestamp
    }

    function GetCurrentBlockDifficulty() public view returns (uint256) {
        return block.difficulty;  
    }

    function GetCurrentBlockNumber() public view returns (uint256) {
        return block.number;      
    }

    function GetCurrentBlockStats() public view returns (uint256,uint256,uint256) {
        return (block.number, block.difficulty, block.timestamp);      
    }
    //////////////////////////// MISC INFO FUNCTIONS ////////////////////////////  









    receive() external payable { }      // oh it's payable alright
}

