// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGWeapons.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUGFYakuza.sol";

contract UGForgeSmith is ReentrancyGuard, Pausable, Ownable {

    struct Stake {
        uint32 tokenId;
        uint32 bloodPerLevel;
        uint32 stakeTimestamp;
        address owner;
    }

    struct BloodStake {
        uint32 amountStaked;
        uint32 sweatClaimTimeStamp;
        uint32 stakeTimestamp;
        address owner;
    }

    /*///////////////////////////////////////////////////////////////
                        WEAPON METALS BIT INDEXes
    //////////////////////////////////////////////////////////////*/
    //lowerweapons (0 - 14)
    uint8 constant STEEL = 0;
    uint8 constant BRONZE = 5;
    uint8 constant GOLD_WEAPON = 10;
    //upper weapons (15 - 29)
    uint8 constant PLATINUM = 15;
    uint8 constant TITANIUM = 20;
    uint8 constant DIAMOND = 25;
    //broken weapons
    uint8 constant BROKEN_STEEL = 30;
    uint8 constant BROKEN_BRONZE = 35;
    uint8 constant BROKEN_GOLD_WEAPON = 40;
    //upper weapons (15 - 29)
    uint8 constant BROKEN_PLATINUM = 45;
    uint8 constant BROKEN_TITANIUM = 50;

    //weapons bit indexes (metal + weapon = bit index (tokenId)
    uint8 constant KNUCKLES = 1;
    uint8 constant CHAINS = 2;
    uint8 constant BUTTERFLY = 3;
    uint8 constant MACHETE = 4;
    uint8 constant KATANA = 5;

    uint8 constant SWEAT = 56;

    uint8 constant STEEL_KEY = 10;
    uint8 constant BRONZE_KEY = 20;
    uint8 constant GOLD_KEY = 40;
    uint8 constant PLATINUM_KEY = 60;
    uint8 constant TITANIUM_KEY = 80;
    uint8 constant DIAMOND_KEY = 100;

    uint8 constant BROKEN_STEEL_KEY = 11;
    uint8 constant BROKEN_BRONZE_KEY = 21;
    uint8 constant BROKEN_GOLD_KEY = 41;
    uint8 constant BROKEN_PLATINUM_KEY = 61;
    uint8 constant BROKEN_TITANIUM_KEY = 81;

    uint256 constant FORGE = 15000;

    uint256 public BASE_REPAIR_FEE = 500;
    // any rewards distributed when no Forges are staked
    uint256 private _unaccountedRewards = 0;
    // amount of $BLOOD due for each forge level staked
    uint256 private _bloodPerLevel = 0;    
    // total sum of Forge Level staked
    uint256 public totalForgeLevelStaked;
    uint256 public totalForgesStaked;
    //maps tokenIds to Stake
    mapping(uint256 => Stake) public stakedForges;
    //maps owner to number of Forges Staked
    mapping(address => uint256) public ownerTotalStakedForges;
    //maps attack scores type to weapon index
    mapping(uint256 => uint256) private attackScoreToWeaponIndex;    
    //Blood staking for Sweat
    uint256 public totalBloodStaked;
    mapping (address => BloodStake) public bloodStakes;

    constructor(address _ugnft, address _ugFYakuza, address _blood, address _ugWeapons, address _ugArena, address _devWallet) {
       require(_devWallet != address(0x00), "devWallet must not be 0 address");
        ugNFT = IUGNFT(_ugnft);
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        uBlood = IUBlood(_blood);
        ugWeapons = IUGWeapons(_ugWeapons);
        ugArena = IUGArena(_ugArena);
        devWallet = _devWallet;

        attackScoreToWeaponIndex[STEEL_KEY] = STEEL;
        attackScoreToWeaponIndex[BRONZE_KEY] = BRONZE;
        attackScoreToWeaponIndex[GOLD_KEY] = GOLD_WEAPON;
        attackScoreToWeaponIndex[PLATINUM_KEY] = PLATINUM;
        attackScoreToWeaponIndex[TITANIUM_KEY] = TITANIUM;
        attackScoreToWeaponIndex[DIAMOND_KEY] = DIAMOND;

        attackScoreToWeaponIndex[BROKEN_STEEL_KEY] = BROKEN_STEEL;
        attackScoreToWeaponIndex[BROKEN_BRONZE_KEY] = BROKEN_BRONZE;
        attackScoreToWeaponIndex[BROKEN_GOLD_KEY] = BROKEN_GOLD_WEAPON;
        attackScoreToWeaponIndex[BROKEN_PLATINUM_KEY] = BROKEN_PLATINUM;
        attackScoreToWeaponIndex[BROKEN_TITANIUM_KEY] = BROKEN_TITANIUM;
    }

    //////////////////////////////////
    //          ERRORS             //
    /////////////////////////////////
    error MismatchArrays();
    error InvalidTokenId();
    error InvalidOwner();
    error Unauthorized();
    error OnlyEOA();

    //////////////////////////////////
    //          EVENTS             //
    /////////////////////////////////
    event TokenStaked(address indexed account, uint256[] tokenIds);
    event TokenUnstaked(address indexed account, uint256[] tokenIds);
    event TokensClaimed(address indexed account, uint256[] tokenIds, uint256 owed, uint256 timestamp);
    event TokenClaimed(address indexed account, uint256 tokenId, uint256 owed, uint256 timestamp);

    //////////////////////////////////
    //          CONTRACTS          //
    /////////////////////////////////
    IUGNFT public ugNFT;
    IUGFYakuza public ugFYakuza;
    IUBlood private uBlood;
    IUGWeapons public ugWeapons;
    IUGArena public ugArena;

    //////////////////////////////////
    //          MODIFIERS          //
    /////////////////////////////////
    modifier onlyAdmin() {
        if(!_admins[msg.sender]) revert Unauthorized();
        _;
    }

    modifier onlyEOA() {
        if(tx.origin != msg.sender) revert OnlyEOA();
        _;
    }

    //////////////////////////////////
    //          VIEW FUNCTIONS     //
    /////////////////////////////////

    function getStakedForgeIDsForUser(address user) public view returns (uint256[] memory){
        //get balance of forges
        uint256 numStakedForges = ownerTotalStakedForges[user];
        uint256[] memory _tokenIds = new uint256[](numStakedForges);
        //loop through user balances until we find all the forges
        uint count;
        uint ttlForges = ugNFT.ttlForges();
        for(uint i=1; count<numStakedForges && i <= ttlForges; i++){
            if(stakedForges[FORGE + i].owner == user){       
                _tokenIds[count] = FORGE + i;
                count++;          
            }
        }
        return _tokenIds;
    }

    function getOwnerStakedBlood(address user) external view returns (uint32) {
        return bloodStakes[user].amountStaked;
    }

    function calculateSweatRewards(address user) public view returns (uint256) {
        BloodStake memory bloodStake = bloodStakes[user];     
        //emit sweat at rate of 1 sweat per 100 Blood per day
        if(block.timestamp <= bloodStake.sweatClaimTimeStamp) return 0;
        return (block.timestamp - bloodStake.sweatClaimTimeStamp) * bloodStake.amountStaked / (100 days ) ;
    }    

    function calculateForgeBloodReward(uint256 tokenId ) public view returns (uint256 owed) {         
        Stake memory stake = stakedForges[tokenId]; 
        IUGNFT.ForgeFightClub memory forge = ugNFT.getForgeFightClub(tokenId);        
        if(_bloodPerLevel > stake.bloodPerLevel) owed += (forge.level) * (_bloodPerLevel - stake.bloodPerLevel)/100000;
    }

    function calculateAllForgeBloodRewards (uint256[] calldata tokenIds) external view returns(uint256) {
        uint256 owed;
        for(uint i; i<tokenIds.length;i++){
            owed += calculateForgeBloodReward(tokenIds[i] );
        }
        return owed;
    }

    function calculateStakingRewards(uint256 tokenId) public view returns (uint256 , uint256 ) {
        uint256 weapon;
        uint256 owed;
        Stake memory stakedForge = stakedForges[tokenId];        
        if(stakedForge.stakeTimestamp > 0){
            //get forge 
            IUGNFT.ForgeFightClub memory forge = ugNFT.getForgeFightClub(tokenId);
            require(forge.size > (forge.level-1)/7, "Invalid Forge Size");
            //get forge expire date
            uint256 forgeExpireTime = forge.lastLevelUpgradeTime + 7 days;
            uint256 claimTilTime = forgeExpireTime > block.timestamp ? block.timestamp : forgeExpireTime;
            uint256 claimTime = claimTilTime > stakedForge.stakeTimestamp ? claimTilTime - stakedForge.stakeTimestamp : 0;
            //need to make sure forge is of proper size
            //basic formula -> (current time - last claim time)/days * forge.level%7
            
            if(forge.level % 7 == 0){
                owed = 7 * claimTime/ 1 days;
            } else owed = (forge.level % 7) * claimTime/ 1 days ;
            //for proper weapon to mint -> (forge.level-1)/ 7 + 1
            weapon = (forge.level-1)/ 7 + 1;
            //all forge minted weapons are steel

        }
        return (weapon, owed);
    }

    function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256[] memory weapons, uint256[] memory amounts) {
        (weapons, amounts) = _calculateAllStakingRewards(tokenIds);
     return(weapons, amounts);
    }

    function _calculateAllStakingRewards(uint256[] memory tokenIds) private view returns (uint256[] memory , uint256[] memory )  {
        uint256[] memory weapons = new uint256[](tokenIds.length);
        uint256[] memory amounts = new uint256[](tokenIds.length);
        for(uint i; i<tokenIds.length;i++){
            (weapons[i], amounts[i]) = calculateStakingRewards(tokenIds[i]);            
        }
        return (weapons, amounts);
    }

    function getBloodPerLevel() external view returns (uint256) {
        return _bloodPerLevel/100000;
    }

    function getBloodRepairFee(uint256 tokenId) external view returns (uint256) {
         if(tokenId % 5 == 0){//if katana
                return (BASE_REPAIR_FEE * 16) * (tokenId / 5);
            }
            else return BASE_REPAIR_FEE * (2 ** ((tokenId % 5) - 1))* (tokenId / 5);
    }

    //////////////////////////////////
    //         WRITE FUNCTIONS     //
    /////////////////////////////////
    function claimManyForgeBloodRewards(uint256[] memory tokenIds) public whenNotPaused  {
        uint256 owed;
        Stake memory stake = stakedForges[tokenIds[0]]; 
        for(uint i; i<tokenIds.length;i++){
            owed += claimForgeBloodRewards(tokenIds[i]);
        }
        uBlood.mint(stake.owner, owed * 1 ether);
    }

    function claimForgeBloodRewards(uint256 tokenId) private returns (uint256) {
        //Get staked forge
        Stake memory stake = stakedForges[tokenId]; 
        //allow owner or Game Contract to call this
        if(stake.owner != _msgSender() && !_admins[_msgSender()]) revert InvalidTokenId();
        IUGNFT.ForgeFightClub memory forge = ugNFT.getForgeFightClub(tokenId);        

        //blood reward section   
        uint256 owed;           
        if(_bloodPerLevel > stake.bloodPerLevel) owed = (forge.level) * (_bloodPerLevel - stake.bloodPerLevel)/100000;
        // Just claim rewards
        Stake memory myStake;
        myStake.tokenId = uint32(tokenId);
        myStake.bloodPerLevel = uint32(_bloodPerLevel);
        myStake.stakeTimestamp = uint32(block.timestamp);
        myStake.owner = stake.owner;
        // Reset stake
        stakedForges[tokenId] = myStake;                 
        emit TokenClaimed(stake.owner, tokenId, owed, block.timestamp);
        return owed;
    }

    function claimStakingRewards(uint256 tokenId) external whenNotPaused {
        //Get staked forge
        Stake memory stake = stakedForges[tokenId]; 
        //allow owner or Game Contract to call this
        if(stake.owner != _msgSender() && !_admins[_msgSender()]) revert InvalidTokenId();
        IUGNFT.ForgeFightClub memory forge = ugNFT.getForgeFightClub(tokenId); 
        uint256 owedWeapons;
        uint256 owedAmounts;               
        (owedWeapons, owedAmounts) = calculateStakingRewards(tokenId); 

        //blood reward section   
        uint256 owed;           
        if(_bloodPerLevel > stake.bloodPerLevel) owed = (forge.level) * (_bloodPerLevel - stake.bloodPerLevel)/100000;
        // Just claim rewards
        Stake memory myStake;
        myStake.tokenId = uint32(tokenId);
        myStake.bloodPerLevel = uint32(_bloodPerLevel);
        myStake.stakeTimestamp = uint32(block.timestamp);
        myStake.owner = stake.owner;
        // Reset stake
        stakedForges[tokenId] = myStake;         

        uBlood.mint(stake.owner, owed * 1 ether);
        ugWeapons.mint(stake.owner, owedWeapons, owedAmounts, "" );
        emit TokenClaimed(stake.owner, tokenId, owed, block.timestamp);
    }

    function claimAllStakingRewards(address user) external whenNotPaused {
        //allow owner or Game Contract to call this
        if(user != _msgSender() && !_admins[_msgSender()]) revert InvalidTokenId();
        //get Forge Ids for User
        uint256[] memory _stakedForgeIds = getStakedForgeIDsForUser(user);        
        uint256[] memory weapons = new uint256[] (_stakedForgeIds.length);
        uint256[] memory amounts = new uint256[] (_stakedForgeIds.length);

        //blood reward section
        uint256 owed;
        Stake memory stake; 
        IUGNFT.ForgeFightClub[] memory forges = ugNFT.getForgeFightClubs(_stakedForgeIds);
        

        for(uint i; i<_stakedForgeIds.length;i++){            
            (weapons[i], amounts[i]) = calculateStakingRewards(_stakedForgeIds[i]); 

            stake = stakedForges[_stakedForgeIds[i]];   

            //blood reward section              
            if(_bloodPerLevel > stake.bloodPerLevel) owed += (forges[i].level) * (_bloodPerLevel - stake.bloodPerLevel)/100000;
            // Just claim rewards
            Stake memory myStake;
            myStake.tokenId = uint32(_stakedForgeIds[i]);
            myStake.bloodPerLevel = uint32(_bloodPerLevel);
            myStake.stakeTimestamp = uint32(block.timestamp);
            myStake.owner = stake.owner;
            // Reset stake
            stakedForges[_stakedForgeIds[i]] = myStake; 

        }

        uBlood.mint(user, owed * 1 ether);
        ugWeapons.batchMint(user, weapons, amounts, "" );
        emit TokensClaimed(stake.owner, _stakedForgeIds, owed, block.timestamp);
    }

    function stakeForges(uint256[] calldata tokenIds) external  whenNotPaused{
        //make sure is owned by sender
        if(!ugNFT.checkUserBatchBalance(msg.sender, tokenIds)) revert InvalidTokenId();
        _stakeForges(_msgSender(), tokenIds);
    }

    function _stakeForges(address account, uint256[] calldata tokenIds) private {
        uint256[] memory amounts = new uint256[](tokenIds.length);
        uint256 levelCnt;
        Stake memory myStake;
        IUGNFT.ForgeFightClub[] memory forges =ugNFT.getForgeFightClubs(tokenIds);
        for(uint i; i < tokenIds.length; i++){
            amounts[i] = 1;
            myStake.tokenId = uint32(tokenIds[i]);
            myStake.stakeTimestamp = uint32(block.timestamp);
            myStake.bloodPerLevel = uint32(_bloodPerLevel);
            myStake.owner = account;       
            levelCnt+= forges[i].level;
            stakedForges[tokenIds[i]] = myStake;
        }
        
        totalForgesStaked += tokenIds.length;
        ownerTotalStakedForges[account] += tokenIds.length;
        totalForgeLevelStaked +=  levelCnt;

        ugNFT.safeBatchTransferFrom(account, address(this), tokenIds, amounts, "");
        emit TokenStaked(account, tokenIds);
    }

    function unstakeForges(uint256[] calldata tokenIds) external nonReentrant onlyEOA  {
        uint256[] memory amounts = new uint256[](tokenIds.length);
        IUGNFT.ForgeFightClub[] memory forges =ugNFT.getForgeFightClubs(tokenIds);
        uint256 levelCnt;
        for(uint i; i < tokenIds.length;i++){
            //make sure sender is ringowner            
            if(stakedForges[tokenIds[i]].owner != _msgSender()) revert InvalidTokenId();
            levelCnt += forges[i].level;
            amounts[i] = 1;
            delete stakedForges[tokenIds[i]];
        }
        totalForgeLevelStaked -=  levelCnt;
        totalForgesStaked -= tokenIds.length;
        ownerTotalStakedForges[_msgSender()] -= tokenIds.length;

        ugNFT.safeBatchTransferFrom(address(this), _msgSender(), tokenIds, amounts, "");
        emit TokenUnstaked(_msgSender(), tokenIds);
    }

    function stakeBloodForSweat(uint256 amount) external whenNotPaused nonReentrant onlyEOA {
        BloodStake memory bloodStake = bloodStakes[_msgSender()] ;
        //claim any previous sweat
        if(bloodStake.amountStaked > 0) claimSweat(_msgSender());

        bloodStake.owner = _msgSender();
        bloodStake.amountStaked += uint32(amount);
        bloodStake.stakeTimestamp = uint32(block.timestamp);        
        bloodStake.sweatClaimTimeStamp = uint32(block.timestamp);
        bloodStakes[_msgSender()] = bloodStake;
        totalBloodStaked += amount;
        //burn amount of blood
        uBlood.burn(_msgSender(),  1 ether * amount);        
    }

    function unstakeBloodForSweat(uint256 amount) external whenNotPaused nonReentrant onlyEOA {
        BloodStake memory bloodStake = bloodStakes[_msgSender()];
        uint256 userSweatBalance = ugWeapons.balanceOf(_msgSender(), SWEAT);
        //delete unclaimed sweat
        bloodStake.sweatClaimTimeStamp = uint32(block.timestamp);
        //get proportion of blood unstaked 
        uint256 pctUnstaked;
        uint256 amountSweatToBurn;
        if(amount < bloodStake.amountStaked){
            pctUnstaked = amount*100 / bloodStake.amountStaked;
            bloodStake.amountStaked -= uint32(amount);
            //reset stake
            bloodStake.stakeTimestamp = uint32(block.timestamp);
            bloodStakes[_msgSender()] = bloodStake;
            //calculate sweat to burn
            amountSweatToBurn = pctUnstaked * userSweatBalance / 100;
        }else {
            amount = bloodStake.amountStaked;
            amountSweatToBurn = userSweatBalance;
            delete bloodStakes[_msgSender()];
        } 
        totalBloodStaked -= amount;
        //burn sweat
        ugWeapons.burn(_msgSender(), SWEAT, amountSweatToBurn);
        //mint amount of blood - 10% unstaking fee
        uBlood.mint(_msgSender(), amount * 1 ether * 90 / 100);
        //burn proportional amount of sweat
    }  

    function claimSweat(address user) public  whenNotPaused {
        //allow owner or Admin Contract to call this
        if(user != _msgSender() && !_admins[_msgSender()]) revert InvalidTokenId();
        uint256 amount = calculateSweatRewards(user);
        bloodStakes[user].sweatClaimTimeStamp = uint32(block.timestamp);
        //mint sweat to user
        ugWeapons.mint(user, SWEAT, amount, "");
    }  

    function equipWeapons(
        uint256[] calldata tokenIds, 
        uint256[] memory weapons
    ) external nonReentrant whenNotPaused onlyEOA {
        if(tokenIds.length != weapons.length) revert MismatchArrays();
        if(!ugArena.verifyAllStakedByUser(_msgSender(), tokenIds)) revert InvalidTokenId();
        
        uint256[] memory FYs = ugFYakuza.getPackedFighters(tokenIds);
        IUGFYakuza.FighterYakuza memory FY;        
        //indexes are token ids and values are amounts
        uint256[] memory amounts = new uint256[](tokenIds.length);
        uint256[] memory idsToMint = new uint256[](tokenIds.length);
        uint8 attackScore;
        uint256 unEquipCount;
        
        for(uint i =0; i<tokenIds.length;i++){
            if(weapons[i] == 0) revert InvalidTokenId();
            FY = unPackFighter(FYs[i]);
           // if(tokenIds[i] > FIGHTER + ttlFYakuzas || tokenIds[i] <= FIGHTER) revert InvalidTokenID();
           //get attack score
           if(weapons[i] <= 30) attackScore = 100;
           if(weapons[i] <= 25) attackScore = 80;
           if(weapons[i] <= 20) attackScore = 60;
           if(weapons[i] <= 15) attackScore = 40;
           if(weapons[i] <= 10) attackScore = 20;
           if(weapons[i] <= 5) attackScore = 10;
            
           //if fighter is equipped, unequip first
           //weapons %5 gives us weapon type 1 = knuckles, 2= chains etc
            if (weapons[i] % 5 == 1){
                if(FY.knuckles > 0){
                    idsToMint[i] = attackScoreToWeaponIndex[FY.knuckles] + KNUCKLES;
                }
               FY.knuckles = attackScore;
            }
            
            if (weapons[i] % 5 == 2){               
               if(FY.chains > 0){
                idsToMint[i] = attackScoreToWeaponIndex[FY.chains] + CHAINS;
               }
               FY.chains = attackScore;
            }
            
            if (weapons[i] % 5 == 3){
               if(FY.butterfly > 0){
                idsToMint[i] = attackScoreToWeaponIndex[FY.butterfly] + BUTTERFLY;
               }
               FY.butterfly = attackScore;
            }
            if (weapons[i] % 5 == 4){
              if(FY.machete > 0){
                idsToMint[i] = attackScoreToWeaponIndex[FY.machete] + MACHETE;
              }
               FY.machete = attackScore;
            }
            if (weapons[i] % 5 == 0){
               if(FY.katana > 0){
                idsToMint[i] = attackScoreToWeaponIndex[FY.katana] + KATANA;
               }
               FY.katana = attackScore;
            }
            amounts[i] = 1;
            if(idsToMint[i] > 0) unEquipCount++;
            
            ugFYakuza.setFighter(tokenIds[i], FY) ;
        }
        //burn equipped weapons
        ugWeapons.batchBurn(_msgSender(), weapons, amounts);

        //creat mint array
        uint256[] memory mintArray = new uint256[](unEquipCount);
        amounts = new uint256[](unEquipCount);
        uint256 count;
        for(uint i =0; i<idsToMint.length && count < unEquipCount;i++){
            if(idsToMint[i] > 0) {
                mintArray[count] = idsToMint[i];
                amounts[count] = 1;
                count++;
            }
        }       
        //mint unequipped weapons
        ugWeapons.batchMint(_msgSender(), mintArray, amounts, "");
    }

    function unEquipWeapons(
        uint256[] calldata tokenIds,
        uint256[] memory weapons
    ) external nonReentrant whenNotPaused onlyEOA {
        if(!ugArena.verifyAllStakedByUser(_msgSender(), tokenIds)) revert InvalidTokenId();
        if(tokenIds.length != weapons.length) revert MismatchArrays();
        IUGFYakuza.FighterYakuza memory FY;
        uint256[] memory FYs = ugFYakuza.getPackedFighters(tokenIds);
        uint256[] memory amounts = new uint256[](weapons.length);
        for(uint i =0; i<tokenIds.length;i++){
            FY = unPackFighter(FYs[i]);
           //check if broken and build array for minting to user
           //knuckles
            if (weapons[i] % 5 == 1){
                if(FY.knuckles > 0) weapons[i] = attackScoreToWeaponIndex[FY.knuckles] + KNUCKLES;                
                FY.knuckles = 0;
            }
            if (weapons[i] % 5 == 2){
                if(FY.chains > 0) weapons[i] = attackScoreToWeaponIndex[FY.chains] + CHAINS ; //if broken
                FY.chains = 0;
            }
            if (weapons[i] % 5 == 3){
                if(FY.butterfly > 0) weapons[i] = attackScoreToWeaponIndex[FY.butterfly] + BUTTERFLY ; //if broken
                FY.butterfly = 0;
            }
            if (weapons[i] % 5 == 4){
                if(FY.machete > 0)  weapons[i] = attackScoreToWeaponIndex[FY.machete] + MACHETE ; //if broken
                FY.machete = 0;
            }
            if (weapons[i] % 5 == 0){
                if(FY.katana > 0) weapons[i] = attackScoreToWeaponIndex[FY.katana] + KATANA ; //if broken
                FY.katana = 0;
            }
            
            //need to handle broken weapons scores etc
            amounts[i] = 1; 
            ugFYakuza.setFighter(tokenIds[i], FY) ;
        }
        ugWeapons.batchMint(_msgSender(), weapons, amounts, "");
    }

    function upgradeWeapons(uint256[] calldata tokenIds, uint256[] calldata amounts) external nonReentrant whenNotPaused onlyEOA {
        //burn weapons for higher weapons
        if(tokenIds.length != amounts.length) revert MismatchArrays();
        uint256 totalBloodRepairFee;
        uint256[] memory upgradedWeapons = new uint256[](tokenIds.length);
        uint256[] memory upgradedAmounts = new uint256[](tokenIds.length);
        for(uint i; i < tokenIds.length; i++){
            if(tokenIds[i] > 25 || tokenIds[i] == 0) revert InvalidTokenId();//cant upgrade diamond or broken weapons
            //create mint array for repaired weapons
            upgradedWeapons[i] = tokenIds[i] + 5;
            upgradedAmounts[i] = amounts[i] / 2; 
            if(upgradedWeapons[i] % 5 == 0){//if katana
                totalBloodRepairFee += BASE_REPAIR_FEE * 16 * (upgradedWeapons[i] / 5) * upgradedAmounts[i];
            }
            else totalBloodRepairFee += BASE_REPAIR_FEE * (2 ** ((upgradedWeapons[i] % 5) - 1)) * (upgradedWeapons[i] / 5) * upgradedAmounts[i];
        }
        burnBlood(_msgSender(), totalBloodRepairFee);
        ugWeapons.batchBurn(_msgSender(), tokenIds, amounts);
        ugWeapons.batchMint(_msgSender(), upgradedWeapons, upgradedAmounts, "");    
    }

    function repairWeapons(uint256[] calldata tokenIds, uint256[] calldata amounts) external whenNotPaused nonReentrant onlyEOA {
        if(tokenIds.length != amounts.length) revert MismatchArrays();
        uint256 totalBloodRepairFee;
        uint256[] memory repairedWeapons = new uint256[](tokenIds.length);
        uint256[] memory repairedAmounts = new uint256[](tokenIds.length);
        for(uint i; i < tokenIds.length; i++){
            if(tokenIds[i] <= 30 || tokenIds[i] == 0 || tokenIds[i] > 55 ) revert InvalidTokenId();
            //create mint array for repaired weapons
            repairedWeapons[i] = tokenIds[i] - 30;
            repairedAmounts[i] = amounts[i] / 2; 
            if(repairedWeapons[i] % 5 == 0){//if katana
                totalBloodRepairFee += BASE_REPAIR_FEE * 16 * (repairedWeapons[i] / 5)  * repairedAmounts[i];
            }
            else totalBloodRepairFee += BASE_REPAIR_FEE * (2 ** ((repairedWeapons[i] % 5) - 1)) * (repairedWeapons[i] / 5) * repairedAmounts[i];
        }
        burnBlood(_msgSender(), totalBloodRepairFee);
        ugWeapons.batchBurn(_msgSender(), tokenIds, amounts);
        ugWeapons.batchMint(_msgSender(), repairedWeapons, repairedAmounts, "");
    }

    function _payForgeBloodRewards(uint amount) private {
        if (totalForgeLevelStaked == 0) { // if there's no staked Forges
            _unaccountedRewards += amount; // keep track of $BLOOD that's due to all Forge Owners
            return;
        }
        // makes sure to include any unaccounted $BLOOD
        _bloodPerLevel += (amount + _unaccountedRewards) * 100000 / totalForgeLevelStaked;
        _unaccountedRewards = 0;
    }

    function addToTotalForgeLevelStaked(uint levelsToAdd) external onlyAdmin {
        totalForgeLevelStaked += levelsToAdd;
    }    

    function burnBlood(address account, uint256 amount) private {
       
        //pay forge owners 25%
        _payForgeBloodRewards(amount / 4);
        //yakuza gets 10%
        ugArena.payRaidRevenueToYakuza(amount /10) ;
        uBlood.burn(account , amount * 1 ether);
        //allocate 4% of all forge fees for continued development
        uBlood.mint(devWallet, amount * 1 ether /25);
    }

    function unPackFighter(uint256 packedFighter) private pure returns (IUGFYakuza.FighterYakuza memory) {
        IUGFYakuza.FighterYakuza memory fighter;   
        fighter.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
        fighter.Gen = uint8(packedFighter>>1)%2 ;
        fighter.level = uint8(packedFighter>>2);
        fighter.rank = uint8(packedFighter>>10);
        fighter.courage = uint8(packedFighter>>18);
        fighter.cunning = uint8(packedFighter>>26);
        fighter.brutality = uint8(packedFighter>>34);
        fighter.knuckles = uint8(packedFighter>>42);
        fighter.chains = uint8(packedFighter>>50);
        fighter.butterfly = uint8(packedFighter>>58);
        fighter.machete = uint8(packedFighter>>66);
        fighter.katana = uint8(packedFighter>>74);
        fighter.scars = uint16(packedFighter>>90);
        fighter.imageId = uint16(packedFighter>>106);
        fighter.lastLevelUpgradeTime = uint32(packedFighter>>138);
        fighter.lastRankUpgradeTime = uint32(packedFighter>>170);
        fighter.lastRaidTime = uint32(packedFighter>>202);
        
        return fighter;
    } 

    /** ONLY OWNER FUNCTIONS */
    function setContracts(address _ugnft, address _ugFYakuza, address _blood, address _ugWeapons, address _ugArena) external onlyOwner {
       
        ugNFT = IUGNFT(_ugnft);
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        uBlood = IUBlood(_blood);
        ugWeapons = IUGWeapons(_ugWeapons);
        ugArena = IUGArena(_ugArena);
    }
    mapping(address => bool) private _admins;
    address private devWallet;
    function setDevWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0x00), "Must not be 0 address");
        devWallet = newWallet;
    }

    function setBaseRepairFee(uint newFee) external onlyOwner {
        BASE_REPAIR_FEE = newFee;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function addAdmin(address addr) external onlyOwner {
        _admins[addr] = true;
    }

    function removeAdmin(address addr) external onlyOwner {
        delete _admins[addr];
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

