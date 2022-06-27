const { verify } = require("../utils/verify")
const hre = require("hardhat");

async function main() {
  
  const Contract = await hre.ethers.getContractFactory("COMMUNIQUE");
  const contract = await Contract.deploy('10000000000000000000000000000');

  await contract.deployed();

  console.log("deployed to:", contract.address);

  await verify(contract.address, [], "contracts/token.sol:COMMUNIQUE")

  //await contract.mint('0x79b5C4CA01C0d4BFa1eB1DA406e82456A0AF736e','10000000000000000000000000')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
