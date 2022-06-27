const { verify } = require("../utils/verify")
const hre = require("hardhat");

async function main() {
  
  const Contract = await hre.ethers.getContractFactory("CMQSTAKEPOOL");
  const contract = await Contract.deploy();

  await contract.deployed();

  console.log("deployed to:", contract.address);

  await verify(contract.address, [], "contracts/cmqpool.sol:CMQSTAKEPOOL")

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
