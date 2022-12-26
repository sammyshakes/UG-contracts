// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "./ERC1155/utils/Pausable.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IRandomizer.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract UGRaidClubs is Ownable, Pausable, ReentrancyGuard {

  struct Stake {
    uint64 bloodPerLevel;
    uint32 stakeTimestamp;
    address owner;
  }

  constructor(
    address _ugnft, 
    address _ugFYakuza, 
    address _blood, 
    address _ugArena, 
    address _ugWeapons, 
    address _randomizer,
    address _devWallet,
    uint256 _devFclubId
  ) {
    ierc1155FY = IERC1155(_ugFYakuza);
    ugNFT = IUGNFT(_ugnft);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    uBlood = IUBlood(_blood);
    ugArena = IUGArena(_ugArena);
    ugWeapons = iUGWeapons(_ugWeapons);
    randomizer = IRandomizer(_randomizer);    
    devWallet = _devWallet;
    devFightClubId = _devFclubId;
  }
  
  //////////////////////////////////
  //          CONTRACTS          //
  /////////////////////////////////
  IERC1155 private ierc1155FY;
  IUGNFT private ugNFT;
  IUGFYakuza private ugFYakuza;
  IUGArena private ugArena;
  IUBlood private uBlood;
  iUGWeapons private ugWeapons;
  IRandomizer private randomizer; 

  //////////////////////////////////
  //          EVENTS             //
  /////////////////////////////////
  event YakuzaTaxPaidFromRaids(uint256 amount, uint256 indexed timestamp);
  event FightClubOwnerBloodRewardClaimed(address indexed user);

  //////////////////////////////////
  //          ERRORS             //
  /////////////////////////////////
  error MismatchArrays();
  //error InvalidTokens(uint256 tokenId);
  error InvalidOwner();
  error InvalidAddress();
  error InvalidTokenId();
  error Unauthorized();
  error OnlyEOA();
  error InvalidSize();

  //////////////////////////////////////////
  uint256 constant FIGHT_CLUB = 20000;

  uint16 constant MAX_SIZE_TIER = 4;
  uint256 private FIGHT_CLUB_BASE_CUT_PCT = 25;
  uint256 private YAKUZA_BASE_CUT_PCT = 5;

  uint256 private maxStakedFightClubRaidSizeTier;
  uint256 private maxStakedFightClubLevelTier;
  uint256 public totalFightClubsStaked;
  uint256 public totalLevelsStaked;  
  uint256 public bloodPerLevel;
  uint256 private devFightClubId;
  address private devWallet;
  

  mapping(address => bool) private _admins;
  //maps fightclub id => Stake
  mapping(uint256 => Stake) public stakedFightclubs;
  //maps fightclub id => owner address
  mapping(uint256 => address) public stakedFightclubOwners;
  //maps owner => number of staked fightclubs
  mapping(address => uint256) public ownerTotalStakedFightClubs;
  //maps FightClub owner => blood rewards
  mapping(address => uint256) public fightClubOwnerBloodRewards;
  
  //Modifiers//
  modifier onlyAdmin() {
    if(!_admins[_msgSender()]) revert Unauthorized();
    _;
  }

  modifier onlyEOA() {
    if(tx.origin != msg.sender) revert OnlyEOA();
    _;
  }

  //////////////////////////////////
  //     EXTERNAL FUNCTIONS      //
  /////////////////////////////////
   
  function getStakedFightClubIDsForUser(address user) external view returns (uint256[] memory){
    //get balance of fight clubs
    uint256 numStakedFightClubs = ownerTotalStakedFightClubs[user];
    uint256[] memory _tokenIds = new uint256[](numStakedFightClubs);
    //loop through user balances until we find all the fighters
    uint count;
    uint ttl = ugNFT.ttlFightClubs();
    for(uint i = 1; count<numStakedFightClubs && i <= FIGHT_CLUB + ttl; i++){
      if(stakedFightclubOwners[FIGHT_CLUB + i] == user){
        _tokenIds[count] = FIGHT_CLUB + i;
        count++;
      }
    }
    return _tokenIds;
  }

  function claimFightClubBloodRewards() external nonReentrant {
    uint256 payout =  fightClubOwnerBloodRewards[msg.sender];
    delete fightClubOwnerBloodRewards[msg.sender];
    uBlood.mint(msg.sender, payout * 1 ether);
    emit FightClubOwnerBloodRewardClaimed(msg.sender);
  } 

  function stakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
    //make sure is owned by sender
    if(!ugNFT.checkUserBatchBalance(msg.sender, tokenIds)) revert InvalidTokenId();    
    IUGNFT.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    if(tokenIds.length != fightclubs.length) revert MismatchArrays();
    
    _stakeFightclubs(msg.sender, tokenIds, fightclubs);
  }  
  
  function _stakeFightclubs(address account, uint256[] calldata tokenIds, IUGNFT.ForgeFightClub[] memory fightclubs) private {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    Stake memory myStake;
    uint256 levelCount;
    uint256 currLevel;
    for(uint i; i < tokenIds.length; i++){
      currLevel = fighclubs[i].level;
      levelCount += (currLevel * fightclubs[i].size);
      stakedFightclubOwners[tokenIds[i]] = account;
      amounts[i] = 1;

      myStake.bloodPerLevel = uint64(bloodPerLevel);
      yStake.stakeTimestamp = uint32(block.timestamp);
      myStake.owner = account; 

      stakedFightclubs[tokenIds[i]] = myStake;
    }

    totalLevelsStaked += levelCount;
    totalFightClubsStaked += tokenIds.length;
    ownerTotalStakedFightClubs[account] += tokenIds.length;     

    ugNFT.safeBatchTransferFrom(account, address(this), tokenIds, amounts, "");
    emit TokenStaked(account, tokenId);
  }

  function claimFightClubs(uint256[] calldata tokenIds, bool unstake) public whenNotPaused nonReentrant {
    require(tokenIds.length > 0, "Empty Array");
    Stake memory myStake;
    IUGNFT.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    if(tokenIds.length != fightclubs.length) revert MismatchArrays();
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    uint256 owed = 0;
    // Fetch the owner so we can give that address the $BLOOD.
    // If the same address does not own all tokenIds this transaction will fail.
    // This is especially relevant when the Game contract calls this function as the _msgSender() - it should NOT get the $BLOOD ofc.
    address account = stakedFightclubs[tokenIds[0]].owner;

    // The _admins[] check allows the Game contract to claim at level upgrades
    // and raid contract when raiding.
    if(account != _msgSender() && !_admins[_msgSender()]) revert InvalidOwner();

    uint256 currLevel;
    uint256 levelCount;
  
    for (uint256 i; i < fightclubs.length; i++) {     
      currLevel = fightclub[i].level;    
      levelCount += currLevel * fightclubs[i].size; 

      account = stakedFightclubs[tokenIds[i]].owner;
      owed += _calculateStakingRewards(tokenIds[i]);   

      if (unstake) {
        delete stakedFightclubs[tokenId]; // Delete old mapping
      } else {
        // Just claim rewards
        Stake memory myStake;
        myStake.bloodPerLevel = uint64(bloodPerLevel);
        myStake.stakeTimestamp = uint32(block.timestamp);
        myStake.owner = account;
        // Reset stake
        stakedFightclubs[tokenId] = myStake; 
      }
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
      totalLevelStaked -= levelCount; // Remove levels from total staked
      totalFightClubsStaked -= tokenIds.length; // Decrease the number of fightclubs staked
      ugNFT.safeBatchTransferFrom(address(this), account, tokenIds, _amounts, ""); // send back Fighter
    }
    
    emit TokensClaimed(account, tokenIds, unstake, owed, block.timestamp);
  }

  function unstakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    IUGNFT.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    uint256 levelCount;
    uint256 currLevel;
    for(uint i; i < tokenIds.length;i++){
      currLevel = fighclubs[i].level;
      levelCount += (currLevel * fightclubs[i].size);
      //make sure sender is clubowner
      if(stakedFightclubOwners[tokenIds[i]] != _msgSender()) revert InvalidTokenId();
      
      delete stakedFightclubOwners[tokenIds[i]];
      amounts[i] = 1;
    }
    totalLevelsStaked -= levelCount;
    totalFightClubsStaked -= tokenIds.length;
    ownerTotalStakedFightClubs[_msgSender()] -= tokenIds.length;

    ugNFT.safeBatchTransferFrom(address(this), _msgSender(), tokenIds, amounts, "");
    //emit TokenUnStaked(_msgSender(), tokenIds);
  }

  function calculateStakingRewards(uint256 tokenId) external view returns (uint256 owed) {
    return _calculateStakingRewards(tokenId);
  }

 function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256 owed) {
    for (uint256 i; i < tokenIds.length; i++) {
      owed += _calculateStakingRewards(tokenIds[i]);
    }
    return owed;
  }

  function _calculateStakingRewards(uint256 tokenId) private view returns (uint256 owed) {
    IUGNFT.ForgeFightClub memory fightclub = ugNFT.getForgeFightClub(tokenId);
    Stake memory myStake = stakedFightclubs[tokenId];
    // Calculate portion of $BLOOD based on level * size
    if(block.timestamp <= myStake.claimTimeStamp){
      if(bloodPerLevel  > myStake.bloodPerRank) owed = (fightclub.level) * (fightclub.size) * (bloodPerLevel - myStake.bloodPerLevel);    
    }    
    return owed;
  }

  function burnBlood(address account, uint256 amount) private {
    uBlood.burn(account , amount * 1 ether);
    //allocate 10% of all burned blood to dev wallet for continued development
    uBlood.mint(devWallet, amount * 1 ether /10);
  }

  /** OWNER ONLY FUNCTIONS */

  function setContracts(
    address _ugArena, 
    address _ugFYakuza, 
    address _ugNFT, 
    address _uBlood,
    address _ugWeapons, 
    address _randomizer
  ) external onlyOwner {
    ierc1155FY = IERC1155(_ugFYakuza);
    ugNFT = IUGNFT(_ugNFT);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    uBlood = IUBlood(_uBlood);
    ugArena = IUGArena(_ugArena);
    ugWeapons = iUGWeapons(_ugWeapons);
    randomizer = IRandomizer(_randomizer);
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setDevWallet(address newWallet) external onlyOwner {
    if(newWallet == address(0)) revert InvalidAddress();
    devWallet = newWallet;
  }

  //////////////////////////////////////
  //     Packed Balance Functions     //
  //////////////////////////////////////
  // Operations for _updateIDBalance
  enum Operations { Add, Sub }
  //map raidId => raiders packed uint 16 bits
  mapping(uint256 => uint256) internal raiders;
  uint256 constant IDS_BITS_SIZE =16;
  uint256 constant IDS_PER_UINT256 = 16;
  uint256 constant RAID_IDS_BIT_SIZE = 32;

  function _viewUpdateBinValue(
    uint256 _binValues, 
    uint256 bitsize, 
    uint256 _index, 
    uint256 _amount, 
    Operations _operation
  ) internal pure returns (uint256 newBinValues) {

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

  function getIDBinIndex(uint256 _id) private pure returns (uint256 bin, uint256 index) {
    bin = _id / IDS_PER_UINT256;
    index = _id % IDS_PER_UINT256;
    return (bin, index);
  }

  function getValueInBin(uint256 _binValues, uint256 bitsize, uint256 _index)
    public pure returns (uint256)
  {
    // Mask to retrieve data for a given binData
    uint256 mask = (uint256(1) << bitsize) - 1;
    
    // Shift amount
    uint256 rightShift = bitsize * _index;
    return (_binValues >> rightShift) & mask;
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
}