// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUGgame.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IRandomizer.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract UGRaidClubs is Ownable, Pausable, ReentrancyGuard {

  struct Stake {
    uint64 bloodPerLevel;
    uint32 stakeTimestamp;
    address owner;
  }

  constructor(
    address _ugnft, 
    address _blood, 
    address _randomizer,
    address _devWallet
  ) {
    ugNFT = IUGNFT(_ugnft);
    uBlood = IUBlood(_blood);
    randomizer = IRandomizer(_randomizer);    
    devWallet = _devWallet;
  }
  
  //////////////////////////////////
  //          CONTRACTS          //
  /////////////////////////////////
  IUGNFT private ugNFT;
  IUBlood private uBlood;
  IRandomizer private randomizer; 
  IUGgame public ugGame;

  //////////////////////////////////
  //          EVENTS             //
  /////////////////////////////////
  event YakuzaTaxPaidFromRaids(uint256 amount, uint256 indexed timestamp);
  event FightClubOwnerBloodRewardClaimed(address indexed user);
  event FightClubsPaid(uint256 amount);

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
  uint16 constant MAX_SIZE_TIER = 4;
  uint16 private DEV_CUT = 5;
  uint256 constant FIGHT_CLUB = 20000;

  
  uint256 private FIGHT_CLUB_BASE_CUT_PCT = 25;
  uint256 private YAKUZA_BASE_CUT_PCT = 5;

  uint256 private maxStakedFightClubRaidSizeTier;
  uint256 private maxStakedFightClubLevelTier;
  uint256 public totalFightClubsStaked;
  uint256 public totalLevelsStaked;  
  uint256 public bloodPerLevel;
  address public devWallet;  

  mapping(address => bool) private _admins;
  //maps fightclub id => Stake
  mapping(uint256 => Stake) public stakedFightclubs;
  //maps fightclub id => owner address
  mapping(uint256 => address) public stakedFightclubOwners;
  //maps owner => number of staked fightclubs
  mapping(address => uint256) public ownerTotalStakedFightClubs;
  //maps FightClub owner => blood rewards
  mapping(address => uint256) public fightClubOwnerBloodRewards;
  // any rewards distributed when no Yakuza are staked
  uint256 private _unaccountedRewards = 0;  
  
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
      currLevel = fightclubs[i].level;
      levelCount += (currLevel * fightclubs[i].size);
      stakedFightclubOwners[tokenIds[i]] = account;
      amounts[i] = 1;

      myStake.bloodPerLevel = uint64(bloodPerLevel);
      myStake.stakeTimestamp = uint32(block.timestamp);
      myStake.owner = account; 

      stakedFightclubs[tokenIds[i]] = myStake;
    }

    totalLevelsStaked += levelCount;
    totalFightClubsStaked += tokenIds.length;
    ownerTotalStakedFightClubs[account] += tokenIds.length;     

    ugNFT.safeBatchTransferFrom(account, address(this), tokenIds, amounts, "");
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

    uint256 currLevel;
    uint256 levelCount;
  
    for (uint256 i; i < fightclubs.length; i++) {     
       
      account = stakedFightclubs[tokenIds[i]].owner;
      // The _admins[] check allows the Game contract to claim at level upgrades
      // and raid contract when raiding.
      if(account != _msgSender() && !_admins[_msgSender()]) revert InvalidOwner();

      owed += _calculateStakingRewards(tokenIds[i]);   

      if (unstake) {
        //tally levels to deduct from total levels staked
        currLevel = fightclubs[i].level;    
        levelCount += currLevel * fightclubs[i].size;

        // Delete old mapping
        delete stakedFightclubs[tokenIds[i]]; 
      } else {
        // Just claim rewards
        Stake memory myStake;
        myStake.bloodPerLevel = uint64(bloodPerLevel);
        myStake.stakeTimestamp = uint32(block.timestamp);
        myStake.owner = account;
        // Reset stake
        stakedFightclubs[tokenIds[i]] = myStake; 
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
        uBlood.mint(account, owed * 1 ether);
      }
    }
  
    if(unstake) {
      totalLevelsStaked -= levelCount; // Remove levels from total staked
      totalFightClubsStaked -= tokenIds.length; // Decrease the number of fightclubs staked
      ownerTotalStakedFightClubs[_msgSender()] -= tokenIds.length;
      ugNFT.safeBatchTransferFrom(address(this), account, tokenIds, _amounts, ""); // send back Fighter
    }

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
    if(bloodPerLevel  > myStake.bloodPerLevel) owed = (fightclub.level) * (fightclub.size) * (bloodPerLevel - myStake.bloodPerLevel); 
    return owed;
  }

  function payRevenueToFightCLubs(uint256 amount) external onlyAdmin {
    _payFightClubs(amount);
  }
  
  function _payFightClubs(uint amount) private {
    if (totalLevelsStaked == 0) { // if there's no staked FightClubs
      _unaccountedRewards += amount; // keep track of $BLOOD that's due to all Yakuza      
      return;
    }
    // makes sure to include any unaccounted $BLOOD 
    //need to * 1000 to prevent claim amount being lower than rank staked causing a 0 result
    uint256 bpr = bloodPerLevel;
    bpr += 100000 * (amount + _unaccountedRewards) / totalLevelsStaked / 1000000;
    bloodPerLevel = bpr;
    _unaccountedRewards = 0;
    emit FightClubsPaid(amount);
  }

  function burnBlood(address account, uint256 amount) private {
    uBlood.burn(account , amount * 1 ether);
    //allocate 10% of all burned blood to dev wallet for continued development
    uBlood.mint(devWallet, amount * 1 ether * DEV_CUT / 100);
  }

  /** OWNER ONLY FUNCTIONS */

  function setContracts(
    address _ugNFT, 
    address _uBlood,
    address _randomizer
  ) external onlyOwner {
    ugNFT = IUGNFT(_ugNFT);
    uBlood = IUBlood(_uBlood);
    randomizer = IRandomizer(_randomizer);
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setGameContract(address _ugGame) external onlyOwner {
    ugGame = IUGgame(_ugGame);
  }

  function setDevCut(uint8 _devCut) external onlyOwner {
    DEV_CUT = _devCut;
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