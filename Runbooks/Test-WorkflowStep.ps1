workflow Test-WorkflowStep
{

	Param
     (
      
         [Parameter (Mandatory=$true)]
         [string] $EstateGroup,
         [Parameter (Mandatory=$true)]
         [String] $EstateShortCode,
         [Parameter (Mandatory=$true)]
         [String] $SourceDomain,
         [Parameter (Mandatory=$true)]
         [String] $DestinationDomain

     )

    $WorkflowName = "Test-WorkflowStep"
    Write-Verbose "($WorkflowName) Initialize parameters and invoke appropriate modules"

    # Workflow Constants (from Azure Automation)
    $RootDomain = Get-AutomationVariable -Name 'RootDomain'
    $GlobalShare = Get-AutomationVariable -Name 'GlobalShare'
    $DC = Get-AutomationVariable -Name 'DC'
    $VMMCLUS = Get-AutomationVariable -Name 'VMMCLUS'
    $RootDirectory = Get-AutomationVariable -Name 'RootDirectory'
    $GroupDomainName = Get-AutomationVariable -Name 'GroupDomainName'
    $DpmServer = Get-AutomationVariable -Name 'DpmServer'
    $AlternateLocation = Get-AutomationVariable -Name 'AlternateLocation'
    $PG = Get-AutomationVariable -Name 'PG'
    $FileServerName = Get-AutomationVariable -Name 'FileServerName'
    $XSUrl = Get-AutomationVariable -Name 'XSUrl'
    $SOFS = Get-AutomationVariable -Name 'SOFS'

    # Workflow Credentials (from Axure Automation)
    $XSUsername = Get-AutomationVariable -Name 'XSUsername'
    $XSPassword = Get-AutomationVariable -Name 'XSPassword'
    
    Write-Output "Initializing Estate Clone for $EstateGroup ($SourceDomain)"

    ################################
    Write-Output "Perform back-end application infrastructure discovery"
    <# TESTED AND WORKING #>
    $BackEnds = InlineScript {
        $SourceDomainFqdn = $Using:SourceDomain+"."+$Using:RootDomain
        Invoke-Command -ScriptBlock { 
            Import-Module Automation.Estate.Cloning.Discovery -Verbose:$false;
		    Get-ActiveBackendServers -EstateShortcode $Using:EstateShortCode -Domain $SourceDomainFqdn -Verbose:$false;
        }
    }

    $BackEndData = $BackEnds.Data
    $FrontEndData = $FrontEnds.Data
    
    ##########################
    # PARALLEL CHILD RUNBOOK #
    ##########################  

	Write-Verbose "Preparing child runbooks parameters and constants"
	# Preparing parameters and constants for VMM Clone
	$VmmRunbookName = "New-VmmClone"
	$VmmRunbookParams = @{
	    "EstateGroup" = $EstateGroup;
	    "SourceDomain" = $SourceDomain;
		"DestinationDomain" = $DestinationDomain;
        "VmmCluster" = $VMMCLUS;
        "RootDomain" = $RootDomain;
		"VirtualMachines" = $BackEndData
	}

    ################################
	
	#Log on the Azure using Login-AzureRmAccount cmdlet
    Write-Verbose "Log on to Azure"
	$AzureCred = Get-AutomationPSCredential -Name 'AzureCred'
	if($AzureCred -ne $null){
		Login-AzureRmAccount -Credential $AzureCred
		Write-Verbose "Log on was successful"
	}else{
		throw "Could not load Azure Credential"
	}

    ################################
	
	#Get required variables from assets
	Write-Verbose "Get required invocation assets"
	$VmmHybridWorkerGroup = Get-AutomationVariable -Name 'secondaryhrwgrpa'
	$AutomationAccountName = Get-AutomationVariable -Name 'autaccountname'	
	$ResourceGroupName = Get-AutomationVariable -Name 'resgroupid'

    $DomainAdminRootHrwCred = Get-AutomationPSCredential -Name "DomainAdminCred"

    #### CHECKPOINT ####
    Checkpoint-Workflow
    ####################

    ################################
	
	#Start VMM Child Runbook
    Write-Output "Clone back-end application infrastructure"
	Write-Verbose "Start a new job for $VmmRunbookName on $VmmHybridWorkerGroup / $AutomationAccountName / $ResourceGroupName"
	$VmmJobID = (Start-AzureRmAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $VmmRunbookName -Parameters $VmmRunbookParams -RunOn $VmmHybridWorkerGroup).JobId
	Write-Verbose "$VmmRunbookName was initiated and job id is: $VmmJobID"

	################################

    # Check for child runbooks job progress 
	$VmmCompletedFlag = $false
    $CompletedFlag = $false
	Do
	{
		  $VmmStatus = (Get-AzureRMAutomationJob $ResourceGroupName -AutomationAccountName $AutomationAccountName -Id $VmmJobID).Status
          
          # handle completion of the child runbooks
		  if($VmmStatus -eq "Completed")
		  {
			  	$VmmCompletedFlag = $true
		  }
          if($VmmCompletedFlag -eq $true)
          {
                Write-Output "Back-end and front-end application infrastructure was successfully cloned"
                $CompletedFlag = $true
          }

          # stop the process when failure of the runbook was encountered
          if($VmmStatus -eq "Stopped" -or $VmmStatus -eq "Stopping" -or $VmmStatus -eq "Failed"){ throw "Back-end application clone was not successfull (job id: $VmmJobID)" }

		  Start-Sleep 60

	}While($CompletedFlag -eq $false)

    #################################
    # END OF PARALLEL CHILD RUNBOOK #
    #################################      
    
    #### CHECKPOINT ####
    Checkpoint-Workflow
    #################################
    # END OF PARALLEL CHILD RUNBOOK #
    #################################      

    ############################
    Write-Output "$EstateGroup ($SourceDomain) clone execution complete"
    
}




