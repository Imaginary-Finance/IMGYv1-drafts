// contracts/imaginaryMint.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface Oracle {
	function latestRoundData() external view returns (
		uint80 roundId,
		int256 answer,
		uint256 startedAt,
		uint256 updatedAt, 
		uint80 answeredInRound
	);
}

abstract contract TokenOracle {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;

	address public assetOracle;			//underlying price
	uint256 public fallbackOraclePrice;

    function _setAssetOracle(
        address oracle,
		uint256 fallbackPrice
    ) internal {
        assetOracle = oracle;
		fallbackOraclePrice = fallbackPrice;
    }

    function assetPrice() public view returns(uint256) {
		uint256 returnPrice = fallbackOraclePrice;
		if(assetOracle != address(0)) {
        	(,int256 price,,,) = Oracle(assetOracle).latestRoundData();
			returnPrice = uint256(price);
		}
        return(returnPrice);
	}

}