BikeSharing System
This project is a decentralized bike-sharing system built on the Stacks blockchain. It allows users to rent bikes, track their usage, and earn loyalty points. The system also includes features for bike maintenance and management.

SmartContract: ST2SBSP5XXWB2PV3GW5PS0VVW68Q5Y3X9R3EQFBJQ.ikesharing
Tech Stack
Smart Contract Language: Clarity

Blockchain: Stacks

Setup Instructions
Prerequisites:

Stacks Wallet (e.g., Leather)

clarinet CLI tool for local development and testing

Clone the repository:

Bash

git clone https://github.com/your-username/bikesharing-system.git
cd bikesharing-system
Install dependencies and run tests:

Bash

clarinet test
Smart Contract Address
Testnet: ST1234567890ABCDEF... (Replace with your actual testnet address)

Mainnet: SP1234567890ABCDEF... (Replace with your actual mainnet address)

How to Use the Project
For Users
Rent a Bike:

Call the rent-bike function with the bikeId and desired duration (in hours).

You will need to have sufficient STX to cover the rental fee and a security deposit.

Return a Bike:

Call the return-bike function with the bikeId and the new location of the bike.

You can also provide optional maintenanceNotes if you noticed any issues with the bike.

Check Bike Status:

Use the get-bike-status read-only function to view the current status of a bike.

For the Contract Owner
Add a New Bike:

Call the add-bike function with a unique bikeId and the initialLocation.

Perform Maintenance:

After a bike has been flagged for maintenance, call the perform-maintenance function to reset its ride counter and make it available again.
