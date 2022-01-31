// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//ANCHOR


contract ImaginaryReserve is Ownable, ReentrancyGuard {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;

	address public iAsset;
	mapping(address => bool) public assets;

	uint256 public enterFee;
	mapping(address => uint256) public exitFees;

	constructor (
		address _iasset,
		address _asset,

		address owner
	) {
		iAsset			 = _iasset;
		enterFee		 = 1001;
		assets[_asset] 	 = true;
		exitFees[_asset] = 999;
		//	   		001% = 001

		transferOwnership(owner);
	}

	//TODO: add functions for asset control

	//enter from asset to iasset
	function swapTo(
		address assetFrom,
		uint256 amountIn
	) public nonReentrant {
		require(amountIn != 0, "IAnchor: Invalid amount.");
		require(assets[assetFrom], "IAnchor: Invalid asset.");

	    uint256 amountOut = amountIn.mul(enterFee).div(1000);
    	require(IERC20(iAsset).balanceOf(address(this)) >= amountOut, "IAnchor: Lacking reserves.");

	    IERC20(assetFrom).transferFrom(msg.sender, address(this), amountIn);
	    // Transfer miMatic to sender
	    IERC20(iAsset).transfer(msg.sender, amountOut);
	}

	//exit from iasset to asset
	function swapFrom(
		uint256 amountIn,
		address assetTo
	) public nonReentrant {
		require(amountIn != 0, "IAnchor: Invalid amount.");
		require(assets[assetTo], "IAnchor: Invalid asset.");

	    uint256 amountOut = amountIn.mul(1000).div(exitFees[assetTo]);
    	require(IERC20(assetTo).balanceOf(address(this)) >= amountOut, "IAnchor: Lacking reserves.");

	    IERC20(iAsset).transferFrom(msg.sender, address(this), amountIn);
	    // Transfer miMatic to sender
	    IERC20(assetTo).transfer(msg.sender, amountOut);
	}
}
