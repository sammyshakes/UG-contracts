// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGgame.sol";
import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract UGYakDen is Ownable, ReentrancyGuard, Pausable {

  struct Stake {
    uint64 bloodPerRank;
    uint32 stakeTimestamp;
    address owner;
  }

  /** CONTRACTS */
  IUGFYakuza public ugFYakuza;
  IUBlood public uBlood;
  IERC1155 public ierc1155;
  IERC1155 public ierc1155FY;
  IUGgame public ugGame;

  //////////////////////////////////
  //          ERRORS             //
  /////////////////////////////////
  error InvalidTokens(uint256 tokenId);
  error InvalidToken();
  error AlreadyStaked();
  error NothingStaked();
  error MismatchArrays();
  error OnlyEOA(address txorigin, address sender);
  error InvalidOwner();

  //////////////////////////////////
  //          EVENTS             //
  /////////////////////////////////
  event TokenStaked(address indexed owner, uint256 indexed tokenId);
  event TokenUnStaked(address indexed owner, uint256 indexed tokenId);
  event TokensStaked(address indexed owner, uint256[] tokenIds, uint256 timestamp);
  event TokensClaimed(address indexed owner, uint256[] indexed tokenIds, bool unstaked, uint256 earned, uint256 timestamp);
  event BloodStolen(address indexed owner, uint256 indexed tokenId, uint256 indexed amount);
  event YakuzaTaxPaid(uint256 indexed amount);
  // Operations for _updateIDBalance
  enum Operations { Add, Sub }

  // amount of $BLOOD earned so far
  uint256 public totalBloodEarned;
  // any rewards distributed when no Yakuza are staked
  uint256 private _unaccountedRewards = 0;
  // amount of $BLOOD due for each rank point staked
  uint256 private _bloodPerRank = 0;

  // Constants regarding bin sizes for balance packing
  uint256 internal constant IDS_BITS_SIZE   = 1;
  uint256 internal constant IDS_PER_UINT256 = 256 / IDS_BITS_SIZE; 
  uint256 internal constant USER_TOTAL_BALANCES_BITS_SIZE   = 32;
  //user total balances bit indexes
  uint256 internal constant YAKUZA_INDEX  = 1;
  // total Yakuza staked
  uint256 public totalYakuzaStaked;
  // total sum of Yakuza rank staked
  uint256 public totalRankStaked;

  // Token IDs balances ; balances[address][id] => balance 
  mapping (address => mapping(uint256 => uint256)) internal stakedBalances;
  // map user address to packed uint256
  mapping (address => uint256) internal userTotalBalances;
  
  
  // maps to all Yakuza 
  mapping(uint256 => Stake) private _yakuzaPatrol;
  
  // admins
  mapping(address => bool) private _admins;

  constructor(address _ugFYakuza, address _blood) {

    ugFYakuza = IUGFYakuza(_ugFYakuza);
    ierc1155FY = IERC1155(_ugFYakuza);
    uBlood = IUBlood(_blood);
  }

  modifier onlyAdmin() {
    require(_admins[_msgSender()], "Arena: Only admins can call this");
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function numUserStakedYakuza(address user) external view returns (uint256){
    return getValueInBin(userTotalBalances[user], USER_TOTAL_BALANCES_BITS_SIZE, YAKUZA_INDEX);
  }

  function getStakedYakuza(uint256 tokenId) public view returns (Stake memory) {
    return _yakuzaPatrol[tokenId];
  }

  function getStakedYakuzas(uint256[] memory tokenIds) public view returns (Stake[] memory yakuzas) {
    yakuzas = new Stake[](tokenIds.length);
    for (uint256 i; i < tokenIds.length; i++) {
      yakuzas[i] = _yakuzaPatrol[tokenIds[i]];
    }
  }

  function getBloodPerRank() external view returns (uint256) {
    return _bloodPerRank;
  }

  function stakedIdsByUser(address user) external view returns (uint256[] memory) {
    uint256 ownerTokenCount = getValueInBin(userTotalBalances[user], USER_TOTAL_BALANCES_BITS_SIZE, YAKUZA_INDEX);
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(user, i);
    }
    return tokenIds;
  }

  function calculateStakingRewards(uint256 tokenId) external view returns (uint256 owed) {
    uint256[] memory _ids = new uint256[](1);
    _ids[0] = tokenId;
    uint256[] memory yakuzas = ugFYakuza.getPackedFighters(_ids);
    return _calculateStakingRewards(tokenId, unPackFighter(yakuzas[0]));
  }

 function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256 owed) {
    uint256[] memory yakuzas = ugFYakuza.getPackedFighters(tokenIds);
    for (uint256 i; i < tokenIds.length; i++) {
      owed += _calculateStakingRewards(tokenIds[i], unPackFighter(yakuzas[i]));
    }
    return owed;
  }

  function _calculateStakingRewards(
    uint256 tokenId, 
    IUGFYakuza.FighterYakuza memory yakuza
  ) private view returns (uint256 owed) {
    Stake memory myStake = getStakedYakuza(tokenId);
    // Yakuza
    // Calculate portion of $BLOOD based on rank
    //divide by 1000 to get back normal bloodPerRank, had to *1000 to prevent 0 result
    if(_bloodPerRank  > myStake.bloodPerRank) owed = (yakuza.rank) * (_bloodPerRank - myStake.bloodPerRank);
    
    return (owed);
  }
  
  function verifyAllStakedByUser(address user, uint256[] calldata _tokenIds) external view returns (bool) {
    for(uint i; i < _tokenIds.length; i++){  
       if(_yakuzaPatrol[_tokenIds[i]].owner != user) return false;
    }
    return true;
  }

  /*///////////////////////////////////////////////////////////////
                    WRITE FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function stakeManyToArena(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
    //get batch balances to ensure rightful owner
    if(!ugFYakuza.checkUserBatchBalance(_msgSender(), tokenIds)) revert InvalidToken();//InvalidTokens({tokenId: tokenId});
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    uint256[] memory FY = ugFYakuza.getPackedFighters(tokenIds);
    IUGFYakuza.FighterYakuza memory yakuza;
    Stake memory myStake;
    uint256 numYaks;
    uint256 rankCnt;

    _addToOwnerStakedTokenList(_msgSender(), tokenIds);
    
    for (uint i = 0; i < tokenIds.length; i++) {   
      yakuza = unPackFighter(FY[i]);
      if(yakuza.isFighter) revert InvalidToken();
      myStake.stakeTimestamp = uint32(block.timestamp);
      myStake.owner = _msgSender();
      _amounts[i] = 1; //set amounts array for batch transfer

      //stake yakuza
      myStake.bloodPerRank = uint64(_bloodPerRank);
      myStake.owner = _msgSender();       
      rankCnt+= yakuza.rank;
      _yakuzaPatrol[tokenIds[i]] = myStake; // Add the Yakuza to Patrol      
      numYaks++;        
      _updateIDStakedBalance(_msgSender(),tokenIds[i], _amounts[i], Operations.Add);
    }
    
    totalYakuzaStaked += numYaks;
    totalRankStaked += rankCnt; // Portion of earnings ranges from 5 to 8    
     
    _updateIDUserTotalBalance(_msgSender(),YAKUZA_INDEX, numYaks, Operations.Add);
  
    ugFYakuza.safeBatchTransferFrom(_msgSender(), address(this), tokenIds, _amounts, "");
    emit TokensStaked(_msgSender(), tokenIds, block.timestamp);
  }

  function payRevenueToYakuza(uint256 amount) external onlyAdmin {
    _payYakuzaTax(amount);
  }
  
  function _payYakuzaTax(uint amount) private {
    if (totalRankStaked == 0) { // if there's no staked Yakuza
      _unaccountedRewards += amount; // keep track of $BLOOD that's due to all Yakuza      
      return;
    }
    // makes sure to include any unaccounted $BLOOD 
    //need to * 1000 to prevent claim amount being lower than rank staked causing a 0 result
    uint256 bpr = _bloodPerRank;
    bpr += 100000 * (amount + _unaccountedRewards) / totalRankStaked / 1000000;
    _bloodPerRank = bpr;
    _unaccountedRewards = 0;
    emit YakuzaTaxPaid(amount);
  }

  function claimManyFromArena(uint256[] calldata tokenIds, bool unstake) external whenNotPaused nonReentrant {
    require(tokenIds.length > 0, "Empty Array");
    uint256[] memory packedFighters = ugFYakuza.getPackedFighters(tokenIds);
    if(tokenIds.length != packedFighters.length) revert MismatchArrays();
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    uint256 owed = 0;
    // Fetch the owner so we can give that address the $BLOOD.
    // If the same address does not own all tokenIds this transaction will fail.
    // This is especially relevant when the Game contract calls this function as the _msgSender() - it should NOT get the $BLOOD ofc.
    address account = getStakedYakuza(tokenIds[0]).owner;

    // The _admins[] check allows the Game contract to claim at level upgrades
    // and raid contract when raiding.
    if(account != _msgSender() && !_admins[_msgSender()]) revert InvalidToken();
    
    
    
    if(unstake) _removeFromOwnerStakedTokenList(_msgSender(), tokenIds);
    for (uint256 i; i < packedFighters.length; i++) {      
      
      account = getStakedYakuza(tokenIds[i]).owner;
      owed += _claimYakuza(tokenIds[i], unstake, unPackFighter(packedFighters[i]));
    
      //set amounts array for batch transfer
      _amounts[i] = 1;
    }
    // Pay out earned $BLOOD
     if (owed > 0) {
      
      uint256 MAXIMUM_BLOOD_SUPPLY = ugGame.MAXIMUM_BLOOD_SUPPLY();
      
      uint256 bloodTotalSupply = uBlood.totalSupply();
      uint256 normalizedSupply = bloodTotalSupply/1e18;
      // Pay out rewards as long as we did not reach max $BLOOD supply
      if (normalizedSupply < MAXIMUM_BLOOD_SUPPLY ) {
        if (normalizedSupply + owed > MAXIMUM_BLOOD_SUPPLY) { // If totalSupply + owed exceeds the maximum supply then pay out only the remainder
          owed = MAXIMUM_BLOOD_SUPPLY - normalizedSupply; // Pay out the rest and that's it, we reached the maximum $BLOOD supply (for now)
        }
        // Pay $BLOOD to the owner
        totalBloodEarned += owed;
        uBlood.mint(account, owed * 1 ether);
      }
    }
  
    if(unstake) {
      ugFYakuza.safeBatchTransferFrom(address(this), account, tokenIds, _amounts, ""); // send back Fighter
    }
    
    emit TokensClaimed(account, tokenIds, unstake, owed, block.timestamp);
  }

  function _claimYakuza(uint256 tokenId, bool unstake, IUGFYakuza.FighterYakuza memory yakuza) private returns (uint256 owed) { 
    Stake memory stake = getStakedYakuza(tokenId);
    uint8 rank = yakuza.rank;
    if(stake.owner != _msgSender() && !_admins[_msgSender()]) revert InvalidOwner();
    
    owed = _calculateStakingRewards(tokenId, yakuza);
    if (unstake) {
      totalRankStaked -= rank; // Remove rank from total staked
      totalYakuzaStaked--; // Decrease the number

      delete _yakuzaPatrol[tokenId]; // Delete old mapping
      _updateIDStakedBalance(stake.owner, tokenId, 1, Operations.Sub);
      _updateIDUserTotalBalance(stake.owner, YAKUZA_INDEX, 1, Operations.Sub);
    } else { // Just claim rewards
      Stake memory myStake;
      myStake.bloodPerRank = uint64(_bloodPerRank);
      myStake.stakeTimestamp = uint32(block.timestamp);
      myStake.owner = stake.owner;
      // Reset stake
      _yakuzaPatrol[tokenId] = myStake; 
    }
    //emit TokenClaimed(stake.owner, tokenId, unstake, owed, block.timestamp);
    return owed;
  }

  function unPackFighter(uint256 packedFighter) private pure returns (IUGFYakuza.FighterYakuza memory) {
    IUGFYakuza.FighterYakuza memory yakuza;   
    yakuza.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
    yakuza.Gen = uint8(packedFighter>>1)%2;
    yakuza.level = uint8(packedFighter>>2);
    yakuza.rank = uint8(packedFighter>>10);
    yakuza.courage = uint8(packedFighter>>18);
    yakuza.cunning = uint8(packedFighter>>26);
    yakuza.brutality = uint8(packedFighter>>34);
    yakuza.knuckles = uint8(packedFighter>>42);
    yakuza.chains = uint8(packedFighter>>50);
    yakuza.butterfly = uint8(packedFighter>>58);
    yakuza.machete = uint8(packedFighter>>66);
    yakuza.katana = uint8(packedFighter>>74);
    yakuza.scars = uint16(packedFighter>>90);
    yakuza.imageId = uint16(packedFighter>>106);
    yakuza.lastLevelUpgradeTime = uint32(packedFighter>>138);
    yakuza.lastRankUpgradeTime = uint32(packedFighter>>170);
    yakuza.lastRaidTime = uint32(packedFighter>>202);
    return yakuza;
  }

  /////////////////////////////////////////
  //     Packed Balance Functions       //
  ///////////////////////////////////////
  
  /**
   * @notice Update the balance of a id for a given address
   * @param _address    Address to update id balance
   * @param _id         Id to update balance of
   * @param _amount     Amount to update the id balance
   * @param _operation  Which operation to conduct :
   *   Operations.Add: Add _amount to id balance
   *   Operations.Sub: Substract _amount from id balance
   */
  function _updateIDStakedBalance(address _address, uint256 _id, uint256 _amount, Operations _operation)
    internal
  {
    uint256 bin;
    uint256 index;

    // Get bin and index of _id
    (bin, index) = getIDBinIndex(_id);

    // Update balance
    stakedBalances[_address][bin] = _viewUpdateBinValue(stakedBalances[_address][bin], IDS_BITS_SIZE, index, _amount, _operation);
  }

  function _updateIDUserTotalBalance(address _address, uint256 _index, uint256 _amount, Operations _operation)
    internal
  {
    // Update balance
    userTotalBalances[_address] = _viewUpdateBinValue(userTotalBalances[_address], USER_TOTAL_BALANCES_BITS_SIZE, _index, _amount, _operation);
  }

  /**
   * @notice Update a value in _binValues
   * @param _binValues  Uint256 containing values of size IDS_BITS_SIZE (the token balances)
   * @param _index      Index of the value in the provided bin
   * @param _amount     Amount to update the id balance
   * @param _operation  Which operation to conduct :
   *   Operations.Add: Add _amount to value in _binValues at _index
   *   Operations.Sub: Substract _amount from value in _binValues at _index
   */
  function _viewUpdateBinValue(uint256 _binValues, uint256 bitsize, uint256 _index, uint256 _amount, Operations _operation)
    internal pure returns (uint256 newBinValues)
  {
    uint256 shift = bitsize * _index;
    uint256 mask = (uint256(1) << bitsize) - 1;

    if (_operation == Operations.Add) {
      newBinValues = _binValues + (_amount << shift);
      require(newBinValues >= _binValues, " OVERFLOW2");
      require(
        ((_binValues >> shift) & mask) + _amount < 2**bitsize, // Checks that no other id changed
        "OVERFLOW1"
      );

    } else if (_operation == Operations.Sub) {
      newBinValues = _binValues - (_amount << shift);
      require(newBinValues <= _binValues, " UNDERFLOW");
      require(
        ((_binValues >> shift) & mask) >= _amount, // Checks that no other id changed
        "viewUpdtBinVal: UNDERFLOW"
      );

    } else {
      revert("viewUpdtBV: INVALID_WRITE"); // Bad operation
    }

    return newBinValues;
  }

  /**
  * @notice Return the bin number and index within that bin where ID is
  * @param _id  Token id
  * @return bin index (Bin number, ID"s index within that bin)
  */
  function getIDBinIndex(uint256 _id)
    public pure returns (uint256 bin, uint256 index)
  {
    bin = _id / IDS_PER_UINT256;
    index = _id % IDS_PER_UINT256;
    return (bin, index);
  }

  /**
   * @notice Return amount in _binValues at position _index
   * @param _binValues  uint256 containing the balances of IDS_PER_UINT256 ids
   * @param _index      Index at which to retrieve amount
   * @return amount at given _index in _bin
   */
  function getValueInBin(uint256 _binValues, uint256 bitsize, uint256 _index)
    public pure returns (uint256)
  {
    // Mask to retrieve data for a given binData
    uint256 mask = (uint256(1) << bitsize) - 1;

    // Shift amount
    uint256 rightShift = bitsize * _index;
    return (_binValues >> rightShift) & mask;
  }

  function _viewUserStakedIdBalance(address _address, uint256 _id)
    internal view returns(uint256)
  {
    uint256 bin;
    uint256 index;

    // Get bin and index of _id
    (bin, index) = getIDBinIndex(_id);

    // return balance
    return getValueInBin(stakedBalances[_address][bin], IDS_BITS_SIZE, index);
  }

  //map user address to packed uint256 bins holding token ids
  mapping (address =>  mapping(uint256 => uint256)) internal _ownerStakedTokenList;
  //map tokenIds to owned indexes
  mapping(uint256 => uint256) internal _ownerStakedTokenIndexes;

   //ENUMERATION
  function _addToOwnerStakedTokenList(address _address, uint256[] memory _tokenIds)
    internal
  {    
    //get balance of fighters    
    uint newIndex = getValueInBin(userTotalBalances[_address], USER_TOTAL_BALANCES_BITS_SIZE, YAKUZA_INDEX);
    uint bin;
    uint index;
    for(uint i; i< _tokenIds.length;i++){
      //16 tokenIds per uint
      bin = newIndex / 16;
      index = newIndex % 16;
      // Update balance
      _ownerStakedTokenList[_address][bin] = _viewUpdateBinValue(_ownerStakedTokenList[_address][bin], 16, index, _tokenIds[i], Operations.Add);
      //update owner index
      bin = _tokenIds[i]/16;
      index = _tokenIds[i] % 16;
      //_updateOwnerTokenIndex(_address, _tokenId, _ownerIndex, _operation);
      _ownerStakedTokenIndexes[bin] = _viewUpdateBinValue(_ownerStakedTokenIndexes[bin], 16, index, newIndex, Operations.Add);
      newIndex++;
    }    
  }

  function _removeFromOwnerStakedTokenList(address _from, uint256[] memory _tokenIds)internal{    
    uint256 lastTokenIndex = getValueInBin(userTotalBalances[_from], USER_TOTAL_BALANCES_BITS_SIZE, YAKUZA_INDEX) - 1;
    //16 tokenIds per uint
    uint256 bin;
    uint256 index;
    uint256 removeTokenIndex;  
    uint256 lastTokenId;
    
    for(uint i; i< _tokenIds.length;i++){
    //16 tokenIds per uint
    lastTokenId = getValueInBin(_ownerStakedTokenList[_from][lastTokenIndex / 16], 16, lastTokenIndex % 16);
    //get token to be removed index
    bin = (_tokenIds[i])/ 16;
    index = (_tokenIds[i]) % 16;
    removeTokenIndex = getValueInBin(_ownerStakedTokenIndexes[bin], 16, index);  
    // When the token to delete is the last token, the swap operation is unnecessary    
    if (_tokenIds[i] != lastTokenId) {     
      Operations _operations;
      uint256 amount;
      if(lastTokenId > _tokenIds[i]){
        _operations = Operations.Add;
        amount = lastTokenId - _tokenIds[i];
      } else {
        _operations = Operations.Sub;
        amount = _tokenIds[i] - lastTokenId;
      }
     
      // Move the last token to the slot of the to-delete token
      _ownerStakedTokenList[_from][removeTokenIndex/16] = _viewUpdateBinValue(_ownerStakedTokenList[_from][removeTokenIndex/16], 16, removeTokenIndex%16, amount, _operations);
      uint256 indexDiff = lastTokenIndex - removeTokenIndex;
      //update new index for moved token by subtracting indexDiff
      _ownerStakedTokenIndexes[(lastTokenId)/16] = _viewUpdateBinValue(_ownerStakedTokenIndexes[(lastTokenId)/16], 16, (lastTokenId)%16, indexDiff, Operations.Sub);
      
    }   
    // This also deletes the contents at the last position of the array
    _ownerStakedTokenIndexes[_tokenIds[i]/16] = _viewUpdateBinValue(_ownerStakedTokenIndexes[_tokenIds[i]/16], 16, _tokenIds[i]%16, getValueInBin(_ownerStakedTokenIndexes[(_tokenIds[i])/16], 16, (_tokenIds[i])%16), Operations.Sub);
    // console.log('removeTokenIndex',removeTokenIndex);
    _ownerStakedTokenList[_from][lastTokenIndex / 16] = _viewUpdateBinValue(_ownerStakedTokenList[_from][lastTokenIndex / 16], 16, lastTokenIndex % 16, getValueInBin(_ownerStakedTokenList[_from][lastTokenIndex/16], 16, lastTokenIndex%16), Operations.Sub);
    
    if(lastTokenIndex > 0 ) lastTokenIndex--;
    }   
  }

  function tokenOfOwnerByIndex(address _owner, uint256 _index) public view virtual returns (uint256) {
    require(_index < getValueInBin(userTotalBalances[_owner], USER_TOTAL_BALANCES_BITS_SIZE, YAKUZA_INDEX), "owner index out of bounds");

    uint256 bin = _index/16;
    uint256 index = _index % 16;
    return getValueInBin(_ownerStakedTokenList[_owner][bin], 16, index);
  }

 

  /** ONLY ADMIN FUNCTIONS */
  function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
  

  /** ONLY OWNER FUNCTIONS */
  function setContracts( address _ugFYakuza, address _blood, address _ugGame) external onlyOwner {
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    ierc1155FY = IERC1155(_ugFYakuza);
    uBlood = IUBlood(_blood);
    ugGame = IUGgame(_ugGame);
  }

  function setGameContract(address _ugGame) external onlyOwner {
    ugGame = IUGgame(_ugGame);
  }

  function setPaused(bool paused) external onlyOwner {
    if (paused) _pause();
    else _unpause();
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

}