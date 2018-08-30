function sql_consulta{
    param([string]$userBD,[string]$pwdBD,[string]$instancia)
	#Select com dados para coletar.
	$sqltxt= @'
	set heading off
	set lines 1000
	set pages 1000
	set feedback off
	select 
		s.sid ||';'|| s.serial# ||';'|| s.username ||';'|| s.machine ||';'||  s.command ||';'|| s.state ||';'|| s.program ||';'||  p.spid ||';'|| s.port ||';'|| s.seconds_in_wait ||';'|| s.wait_time_micro
	from
	 v$session s ,
	 v$process p 
	where 
		s.paddr = p.addr;
		exit
'@
	#Consultar na instancia oracle.
	$txt = $sqltxt | c:\oracle\product\11.2.0\client_1\BIN\sqlplus.exe -s ${userBD}/${pwdBD}@${instancia}
	#Eliminação de campos em branco da consultar.
	$txt= $txt -split "`n" | where-object {$_ -notlike ""} 
    return $txt
}


function tb_sql{
	param([System.Object[]]$text,[string]$data)
	#Separando campos.
	$text=$text -split ";" # | where-object {$_ -notlike ""}
	#Criação da object
	$tabela=New-Object psobject
	$tabela | Add-Member -MemberType noteproperty -Name BSID -value $text[0]
	$tabela | Add-Member -MemberType noteproperty -Name BSERIAL -value $text[1]
	$tabela | Add-Member -MemberType noteproperty -Name BUSERNAME -value $text[2]
	if($text -match "\\"){
		$temp= ($text[3] -split "\\")[1]
	}else{
		$temp= $text[3] 
	}		
	$tabela | Add-Member -MemberType noteproperty -Name BMACHINE -value $temp
	$tabela | Add-Member -MemberType noteproperty -Name BCOMMANDO -value $text[4]
	$tabela | Add-Member -MemberType noteproperty -Name BSTATE -value $text[5]
	$tabela | Add-Member -MemberType noteproperty -Name BPROGRAM -value $text[6]
	$tabela | Add-Member -MemberType noteproperty -Name BSPID -value $text[7]
	$tabela | Add-Member -MemberType noteproperty -Name BPORT -value $text[8]
	$tabela | Add-Member -MemberType noteproperty -Name BSECONWAIT -value $text[9]
	$tabela | Add-Member -MemberType noteproperty -Name BCPUWAIT -value $text[10]
	$tabela | Add-Member -MemberType noteproperty -Name BWAITTIMEMICRO -value $text[11]
    $tabela | Add-Member -MemberType noteproperty -Name data -value $data



	
	return $tabela
}
function ssh_consulta{
    param([string]$maquinaLN,[string]$pwdLN,[string]$userLN)
    Import-Module SSH-Sessions
    New-SshSession -ComputerName $maquinaLN  -Username $userLN -Password $pwdLN
	#Conexão SSH com servidor.
	$ssh=Invoke-SshCommand -ComputerName $maquinaLN -Command {ps -aux } -Quiet
    Remove-SshSession -ComputerName $maquinaLN
	#Formatação do texto.
    $texto= $ssh -split "`n"
    return 	$texto

}

function tb_ssh{
	param([System.Object[]]$text,[string]$data)
	#Separando campos.
	$text=$text -split " " # | where-object {$_ -notlike ""}
	#Criação da object
	$tabela2=New-Object psobject -Property @{
        pid = $text[1]
        cpu = $text[2]
        mem = $text[3]
        start = $text[8]
        time = $text[9]
        command = ($text[10..20] -join " ")
        data = $data
    }
	
	#Adicionando o resultado na variavel ps.
	$ps += $tabela2;
    return $ps
	
}
function win_consulta{
	#A função receber maquina como parametro.
	param([string]$maquina,[string]$ipLN,[string]$data)
	#Criar pssession.
	
    $s = New-PSSession -ComputerName $maquina
	#bloco de teste.
	try {
		#Execução de comando remoto para coletar.
		[System.Object[]]$net +=Invoke-Command -Session $s -ScriptBlock { Get-NetTCPConnection -RemotePort 1521  -RemoteAddress $args[0]  | select LocalAddress,LocalPort,RemoteAddress,RemotePort,State,AppliedSetting,OwningProcess, @{name="MCPU";expression={ (Get-Process -id $_.OwningProcess | select cpu).cpu}}, @{name="data";expression={ $args[1]}}}  -ArgumentList $ipLN,$data
	}
	#Se falhar
	catch{
		#Mensagem de erro.
		write-host "$maquina não tem session ou esta bloqueada" 
	}    
	#Removendo a conexão.
	Remove-PSSession -Session $s
    return $net
}
function resultado_win{
    param([System.Object[]]$tab_win,[System.Object[]]$final)
    $fnet= ($tab_win).where({$_.LocalPort -eq $final.BPORT -and $_.data -eq $final.data }) | select-object  OwningProcess, MCPU,LocalPort   
    return $fnet
}
function resultado_ssh{
    param([System.Object[]]$tab_ssh,[System.Object[]]$final)
    $fps=  ($tab_ssh).where({$_.pid -eq $final.BSPID -and $_.data -eq $final.data })  | Select-Object pid,cpu,mem,start,time,command
    return $fnet
}


Import-Module SSH-Sessions
workflow sql {
    $userBD="" #Usuario da instancia.
    $pwdBD="" #Senha da instancia.
    $instancia="" #Nome da instancia.

    $maquinaLN="" # nome do servidor.
    $userLN="" #Usuario do servidor
    $pwdLN="" #senha do servidor
    $ipLN="" #ip do servidor

    $maquinaWIN="" #servidores windows
    $TempoColeta=1

    #Local onde arquivo sera salvo.
	$local_arquivo="c:\teste.csv"
	#Quantidade coletas
	$quantidade= 10 
	#Criação da variaveis global.
	$completo=@()   
    $txt_sql=@()
    $txt_ssh=@()  
    $tab_sql=@()
    $tab_ssh=@()
    $tab_win=@()
        
    for($x=0; $x -ne $quantidade; $x++){        
        sleep $TempoColeta
        $data=get-date -Format "dd/MM/yyyy HH:mm:ss:ffff"
        parallel{
            $workflow:txt_sql+=sql_consulta -userBD $userBD -pwdBD $pwdBD -instancia $instancia
            $workflow:txt_ssh+= ssh_consulta -maquinaLN $maquinaLN -userLN $userLN -pwdLN $pwdLN
            $workflow:tab_win+= win_consulta -maquina $maquinaWIN -ipLN $ipLN -data $data
        
        }        
        
        foreach -parallel ($text in $txt_sql) {
            $workflow:tab_sql+=tb_sql  -text $text -data $data 
        }
        foreach -parallel ($text in $txt_ssh){
            $workflow:tab_ssh += tb_ssh -text $text  -data $data 
        }
    }
    foreach -parallel($final in $tab_sql){
	   #Filtro de porta no windows.
       parallel{
           $fnet= resultado_win -tab_win $tab_win -final $final		    
	       #Filtro de processo no linux.
	       $fps=  resultado_ssh -tab_ssh $tab_ssh -final $final
       }
	   #Criando o resultado Final.
       $resultado=New-Object psobject -Property @{
          ORACLE_SID = $final.bsid
          ORACLE_USERNAME = $final.BUSERNAME
          ORACLE_MAQUINA = $final.BMACHINE
          ORACLE_STATE = $final.BSTATE
          ORACLE_PROGRAMA = $final.BPROGRAM
          ORACLE_PORTA_CLIENTE= $final.BPORT
          ORACLE_SPID= $final.BSPID
          ORACLE_SECONWAIT =$final.BSECONWAIT
          ORACLE_CPUWAIT = $final.BCPUWAIT
          LINUX_PID = $fps.pid
          LINUX_CPU = $fps.cpu
          LINUX_MEMORIA = $fps.mem
          LINUX_START = $fps.start
          LINUX_TIME = $fps.time
          LINUX_COMANDO = $fps.command
          WINDOWS_PID = $fnet.OwningProcess
          WINDOWS_CPU = $fnet.MCPU
          WINDOWS_PORTA = $fnet.LocalPort
          "DATA COLETA" = $final.data               
       }            
	   $workflow:completo += $resultado 
    } 
    return $completo
    #$completo | Export-Csv $local_arquivo -Delimiter ";" -Append
}
$completo=sql



$local_arquivo="c:\teste.csv" #local do arquivo
$completo | Export-Csv $local_arquivo -Delimiter ";" -Append

