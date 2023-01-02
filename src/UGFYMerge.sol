// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUBlood.sol";

contract Merge is ReentrancyGuard, Ownable, Pausable {

    /** CONTRACTS */
    IUGFYakuza private ugFYakuza;
    IUGArena private ugArena;
    IUBlood private uBlood;

    constructor(
        address _ugFYakuza,
        address _ugArena,
        address _ublood
    ){
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        ugArena = IUGArena(_ugArena);
        uBlood = IUBlood(_ublood);
    }

    //Errors
    error InvalidOwner();
    error InvalidAmount();
    error InvalidAccount();
    error Unauthorized();
    error NotEnough();

    //Events
    event YakuzaTaxPaid(uint256 indexed amount);
    event ResurrectedId(uint256 indexed tokenId, uint256 imageId);
    event FighterMerged(IUGFYakuza.FighterYakuza _fighter, BurnedFighter _burnedFighter);

    struct BurnedFighter {
        uint128 tokenId;
        uint128 imageId;
    }

    BurnedFighter[] public graveyard;
    uint256 public mergePrice = 250000;
    mapping(address => bool) private _admins; 

    modifier onlyAdmin() {
        if(!_admins[_msgSender()]) revert Unauthorized();
        _;
    }

    function mergeFighters(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        IUGFYakuza.FighterYakuza memory _fighter1;
        IUGFYakuza.FighterYakuza memory _fighter2;
        IUGFYakuza.FighterYakuza memory fighter;
        
        //verify ownership of oldfighter to msgSender
        if(!ugFYakuza.checkUserBatchBalance(_msgSender(), tokenIds)) revert InvalidOwner();

        _fighter1 = ugFYakuza.getFighter(tokenIds[0]);
        _fighter2 = ugFYakuza.getFighter(tokenIds[1]);

        fighter.isFighter = true;
        fighter.Gen = 0;
        fighter.level = _fighter1.level;
        fighter.rank = 0;
        fighter.courage = _fighter1.courage > _fighter2.courage ? _fighter1.courage : _fighter2.courage;
        fighter.cunning = _fighter1.cunning > _fighter2.cunning ? _fighter1.cunning : _fighter2.cunning;
        fighter.brutality = _fighter1.brutality > _fighter2.brutality ? _fighter1.brutality : _fighter2.brutality;
        fighter.knuckles = _fighter1.knuckles;
        fighter.chains = _fighter1.chains;
        fighter.butterfly = _fighter1.butterfly;
        fighter.machete = _fighter1.machete;
        fighter.katana = _fighter1.katana;
        fighter.scars = _fighter1.scars;
        fighter.imageId = _fighter1.imageId;
        fighter.lastLevelUpgradeTime = uint32(block.timestamp);
        fighter.lastRankUpgradeTime = uint32(block.timestamp);
        fighter.lastRaidTime = uint32(block.timestamp);

        burnBlood(_msgSender(), mergePrice);
        //add burned fighters id and image id to graveyard mapping
        BurnedFighter memory burnedFighter;
        burnedFighter = BurnedFighter({
            tokenId: uint128(tokenIds[1]),
            imageId: uint128(_fighter2.imageId)
        });
        graveyard.push(burnedFighter);
        ugFYakuza.burn(_msgSender(), tokenIds[1]);    
        
        ugFYakuza.setFighter(tokenIds[0], fighter);   

        emit FighterMerged(fighter, burnedFighter) ;
    }

    function burnBlood(address account, uint256 amount) private {
        if(account == address(0x00)) revert InvalidAccount();
        if(amount == 0) revert InvalidAmount();
        //yakuza gets 10%
        ugArena.payRaidRevenueToYakuza(amount /10) ;
        uBlood.burn(account , amount * 1 ether);
        emit YakuzaTaxPaid(amount /10);
    }

    function getGraveyardLength() external view returns (uint256) {
        return graveyard.length;
    }

    /*///////////////////////////////////////////////////////////////
                        ONLY OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addAdmin(address addr) external onlyOwner {
        _admins[addr] = true;
    }

    function removeAdmin(address addr) external onlyOwner {
        delete _admins[addr];
    }

    function setMergePrice(uint256 amount) external onlyOwner {
        mergePrice = amount;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }  

    /** ONLY ADMIN FUNCTIONS */
    function resurrectId() external onlyAdmin returns (uint256, uint256 ){
        require(graveyard.length > 0, "Graveyard is empty");
        BurnedFighter memory _burnedFighter;
        _burnedFighter.tokenId = graveyard[graveyard.length -1].tokenId;
        _burnedFighter.imageId = graveyard[graveyard.length -1].imageId;
        graveyard.pop();
        emit ResurrectedId(_burnedFighter.tokenId, _burnedFighter.imageId);
        return (_burnedFighter.tokenId, _burnedFighter.imageId);
    }

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