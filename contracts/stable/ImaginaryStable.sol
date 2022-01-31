// contracts/imaginaryToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//import "hardhat/console.sol";

contract ImaginaryStable is Ownable, Pausable, AccessControl, ERC20 {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;

	event AuthorizedMint(
		address mint
	);
	event AuthorizedBurn(
		address mint
	);

	event SetDelay(
		uint256 newDelay
	);

    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

	uint256 public minimumRequestDelay;
	
	uint256 public ceilingShift;
	
	uint256 public maxMintSway;
	uint256 public maxBurnSway;
	uint256 public HODLscalar;

	//		mint	
	mapping(address => uint256) public totalMinted;
	mapping(address => uint256) public totalBurned;
	
	mapping(address => uint256) public lastMintingTime;
	mapping(address => uint256) public lastBurningTime;
	
	constructor(
		string memory name,
		string memory symbol,

		address owner
	) ERC20(name, symbol) {

		//TODO: set financial variables

		//1 day ~ 86400
		minimumRequestDelay = 86400*3;

		ceilingShift = 1000000; //1M

		maxMintSway = ceilingShift.div(2); //500K
		maxBurnSway = maxMintSway;

		HODLscalar = 2; //burn prevention

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, address(this));

		transferOwnership(owner);
	}

	function shouldMint(
		address mint
	) public view returns(bool) {
		if(paused() || !hasRole(MINTER_ROLE, mint)) {
			return(false);
		}
		(bool neg, uint256 margin) = collapseSupply(mint);
		return (
			(block.timestamp.sub(lastMintingTime[mint]) > minimumRequestDelay) &&
			(!neg ? (margin <= maxMintSway) : true)
		);
	}

	function authorizedMint(
		address mint
	) internal {
		uint256 newMintAmount = totalMinted[mint].add(ceilingShift);
		assert(newMintAmount > totalMinted[mint]);

		lastMintingTime[mint] = block.timestamp;
		totalMinted[mint] = newMintAmount;
		_mint(mint, ceilingShift.mul(10**decimals()));		
		//console.log("MINTED");
		emit AuthorizedMint(mint);
	}

	function requestMint(
		address mint
	) external onlyRole(MINTER_ROLE) returns(bool) {
		bool should = shouldMint(mint);
		if(!should) {
			return(false);
		}
		require(should, "iStable: You shouldn't");
		authorizedMint(mint);
		return(true);
	}

	function shouldBurn(
		address mint
	) public view returns(bool) {
		if(paused() || !hasRole(MINTER_ROLE, mint)) {
			return(false);
		}
		(bool neg, uint256 margin) = collapseSupply(mint);
		return (
			(block.timestamp.sub(lastBurningTime[mint]) > minimumRequestDelay) &&
			(neg ? true : (margin > maxBurnSway.mul(HODLscalar)))
		);
	}

	function authorizedBurn(
		address mint
	) internal {
		uint256 newBurnAmount = totalBurned[mint].add(ceilingShift);
		assert(newBurnAmount > totalBurned[mint]);

		lastBurningTime[mint] = block.timestamp;
		totalBurned[mint] = newBurnAmount;
		_burn(mint, ceilingShift.mul(10**decimals()));	
		//console.log("BURNED");
		emit AuthorizedBurn(mint);
	}

	function requestBurn(
		address mint
	) external onlyRole(MINTER_ROLE) returns(bool) {
		bool should = shouldBurn(mint);
		if(!should) {
			return(false);
		}
		require(should, "iStable: You shouldn't");
		authorizedBurn(mint);
		return(true);
	}

	//TOKEN CONTROL
	function pauseMech() external onlyOwner whenNotPaused {
		_pause();
	}

	function unpauseMech() external onlyOwner whenPaused {
		_unpause();
	}


	function SetMinimumRequestDelay(uint256 _newDelay) external onlyOwner {
		minimumRequestDelay = _newDelay;
		emit SetDelay(_newDelay);
	}


	function overrideMint(
		address mint
	) external onlyOwner {
		authorizedMint(mint);
	}

	function overrideBurn(
		address mint
	) external onlyOwner {
		authorizedBurn(mint);
	}

	function registerMint(
		address mint
	) external onlyOwner {
		grantRole(MINTER_ROLE, mint);
	}

	function revokeMint(
		address mint
	) external onlyOwner {
		revokeRole(MINTER_ROLE, mint);
	}

	//HELPERS
	function collapseSupply(
		address mint
	) internal view returns(bool, uint256) {
		uint256 minted = totalMinted[mint];
		uint256 burned = totalBurned[mint];
		if(minted == burned) {
			return(false, 0);
		}
		if(minted > burned) {
			return(false, minted.sub(burned));
		} else {
			return(true, burned.sub(minted));
		}
	}
}