# Set up a Coric Azure environment

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndyHerb%2FAzure-Resource-Group%2Fmaster%2FCoric-ARM-Deployment%2FcoricAzureDeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAndyHerb%2FAzure-Resource-Group%2Fmaster%2FCoric-ARM-Deployment%2FcoricAzureDeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

<p>This template deploys a Coric environment into Azure.</p>
<p>It creates shared resources of Storage, Network, NSGs and Administrative VMs before creating one environment (Prod, UAT, Dev, etc.) with the provided number of resource types</p>