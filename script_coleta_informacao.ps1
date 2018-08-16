#Função realizar consultar na instancia oracle
function sql_consulta(){
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
	$global:txt = $sqltxt | sqlplus -s ${userBD}/${pwdBD}@${instancia}
	#Eliminação de campos em branco da consultar.
	$global:txt= $txt -split "`n" | where-object {$_ -notlike ""} 
}
#Função para criação da tabela com dados da consultar.
function tb_sql(){
	#Chamada da função para realizar consultar.
	sql_consulta
	#Loop para criação da tabela.
	foreach($text in $txt){
		#Separando campos.
		$text=$text -split ";" #| where-object {$_ -notlike ""}
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
		#Adicionando o resultado na variavel sql.
		$global:sql+= $tabela
	}
}
#funçaõ para consultar no servidor linux.
function ssh_consulta(){
	#Conexão SSH com servidor.
	$ssh=Invoke-SshCommand -ComputerName $li_maquina -Command {ps -aux } -Quiet
	#Formatação do texto.
	$global:texto= $ssh -split "`n"
}
#Criação da tabela com resultado do ssh.
function tb_ssh(){
	#Chamada da função consultar ssh.
	ssh_consulta
	#Loop para criação da tabela.
	foreach( $text in $texto){
		#Separando campos.
		$text=$text -split " " # | where-object {$_ -notlike ""}
		#Criação da object
		$tabela2=New-Object psobject
		$tabela2 | Add-Member -MemberType noteproperty -Name USER -value $text[0]
		$tabela2 | Add-Member -MemberType noteproperty -Name PID -value $text[1]
		$tabela2 | Add-Member -MemberType noteproperty -Name CPU -value $text[2]
		$tabela2 | Add-Member -MemberType noteproperty -Name MEM -value $text[3]
		$tabela2 | Add-Member -MemberType noteproperty -Name VSZ -value $text[4]
		$tabela2 | Add-Member -MemberType noteproperty -Name RSS -value $text[5]
		$tabela2 | Add-Member -MemberType noteproperty -Name TTY -value $text[6]
		$tabela2 | Add-Member -MemberType noteproperty -Name STAT -value $text[7]
		$tabela2 | Add-Member -MemberType noteproperty -Name START -value $text[8]
		$tabela2 | Add-Member -MemberType noteproperty -Name TIME -value $text[9]
		$final= $text[10..20] -join " "
		$tabela2 | Add-Member -MemberType noteproperty -Name COMMAND -value $final
		#Adicionando o resultado na variavel ps.
		$global:ps += $tabela2;
	}
}
#Função para coletar de informação maquina windows.
function win_consulta(){
	#A função receber maquina como parametro.
	param([string]$maquina)
	#Criar pssession.
	$s = New-PSSession -ComputerName $maquina
	#bloco de teste.
	try {
		#Execução de comando remoto para coletar.
		$global:net +=Invoke-Command -Session $s -ScriptBlock { Get-NetTCPConnection -RemotePort 1521  -RemoteAddress $args[0]  | select LocalAddress,LocalPort,RemoteAddress,RemotePort,State,AppliedSetting,OwningProcess, @{name="MCPU";expression={ (Get-Process -id $_.OwningProcess | select cpu).cpu}}}  -ArgumentList $iporacle
	}
	#Se falhar
	catch{
		#Mensagem de erro.
		write-host "$maquina não tem session ou esta bloqueada" 
	}
	#Removendo a conexão.
	Remove-PSSession -Session $s
}
#Função para criação do relatorio final.
function relatorio(){
	#Loop para criar o relatorio.
	foreach($final in $sql){
		#Filtro de porta no windows.
		$fnet= $net | where-object {$_.LocalPort -eq $final.BPORT } | select-object  OwningProcess, MCPU,LocalPort
		#Filtro de processo no linux.
		$fps=  $ps | where-object {$_.pid -eq $final.BSPID }  | Select-Object pid,cpu,mem,start,time,command
		#Criando o resultado Final.
		$global:completo += $final | select-object BSID,BSERIAL,BUSERNAME,BMACHINE,BSTATE,BPROGRAM,BPORT,BSPID,BSECONWAIT,BCPUWAIT, @{name="SPID";expression={$fps.pid}}, @{name="SCPU";expression={$fps.cpu}}, @{name="SMEM";expression={$fps.mem}}, @{name="SSTART";expression={$fps.start}}, @{name="STIME";expression={$fps.time}}, @{name="SCOMANDO";expression={$fps.command}}, @{name="WPID";expression={$fnet.OwningProcess}}, @{name="WCPU";expression={$fnet.MCPU}},@{name="WPORT";expression={$fnet.LocalPort}},@{name="Data Coleta";expression={$data}}

	}
}
#Função para criação relatorio historico.
function RelatorioHistorico(){
	#Local onde arquivo sera salvo.
	$local_arquivo=Read-Host "Digite o local onde arquivo historico sera salvo" #c:\teste.csv"
	#Quantidade coletas
	$quantidade= Read-Host "Digite a quantidade coleta"  
	#Criação da variaveis global.
	$global:completo=@()
	#Loop para execução.
	for($x=0; $x -ne $quantidade; $x++){
		#tempo de wait ate proxima coleta.
		sleep $TempoColeta
		#criação da variaveis global.
		$global:sql=@()
		#Chamada da função de resultado do sql.
		tb_sql
		#criação da variaveis global.
		$global:ps=@()
		#Chamada da função de resultado dos dados linux.
		tb_ssh
		#criação da variaveis global.
		$global:net=@()
		#Loop para coleta de dados maquinas windows.
		foreach($temp in $maquinas){
			#Chamada da função de resultado dos dados windows.
			win_consulta -maquina $temp
		}
		#Coleta da hora.
		$global:data=get-date -Format "dd/MM/yyyy HH:mm:ss"
		#Chamada da função para criar relatorio.
		relatorio		
	}
	#Gravando o arquivo em formato csv.
	$completo | Export-Csv $local_arquivo -Delimiter ";" -Append
}
# Função para exibição de resultado somente na tela.
function visual(){	
	# loop de execução.
	while( $true ){
		#tempo de wait ate proxima coleta.
		sleep $TempoColeta
		#criação da variaveis global.
		$global:completo=@()
		#criação da variaveis global.
		$global:sql=@()
		#Chamada da função de resultado do sql.
		tb_sql
		#criação da variaveis global.
		$global:ps=@()
		#Chamada da função de resultado dos dados linux.
		tb_ssh
		#criação da variaveis global.
		$global:net=@()
		#Loop para coleta de dados maquinas windows.
		foreach($temp in $maquinas){
			#Chamada da função de resultado dos dados windows.
			win_consulta -maquina $temp
		}
		#Coleta da hora.
		$global:data=get-date -Format "dd/MM/yyyy HH:mm:ss"
		#Chamada da função para criar relatorio.
		relatorio
		#Teste variavel vazia.
		if(![string]::IsNullOrEmpty($wpid)){
			#Aplicação do filtro por processo windows.
			$global:completo = $global:completo | where-object {$_.WPID -eq $wpid}
		}
		#Teste variavel vazia.
		if(![string]::IsNullOrEmpty($lpid)){
			#Aplicação do filtro por processo linux.
			$global:completo = $global:completo | where-object { $_.SPID -eq $lpid}
		}
		#Teste variavel vazia.
		if(![string]::IsNullOrEmpty($bsdi)){
			#Aplicação do filtro por SID do oracle.
			$global:completo = $global:completo | where-object { $_.BSID -eq $bsdi}
		}
		#Limpeza da tela.
		Clear-Host
		#Exibição do resultado.
		$global:completo | format-list
	}
}
#Modulo para fazer ssh.
Import-Module SSH-Sessions
#Usuario do banco de dados.
$userBD="teste"
#Senha do banco de dados.
$pwdBD="teste"
#Nome da instancia de banco de dados.
$instancia=Read-Host "Digite nome da instancia: "
#Ip da instancia oracle 
$iporacle=Read-Host "Digite o ip da instancia Oracle: " 
#Nome de todos servidores windows. 
$maquinas=Read-Host "Digite o nome servidores windows seperado por virgula: " 
#Fazendo a seperação de servidor.
$maquinas= $maquinas -split ","
#Tempo de coleta em segundo.
$TempoColeta=Read-Host "Digite o tempo de coleta em segundo"
#Opção para habilitar o historico.
$historico=Read-Host "Deseja historico(s/n)? "
#Nome do servidor linux
$li_maquina=Read-Host "Digite o nome servidores linux: "
#Nome do usuario do servidor linux.
$usr_maquina=Read-Host "Digite a user servidores linux: "
#Senha do usuario do servidor linux.
$pw_maquina=Read-Host "Digite a senha servidores linux: "
#Criação da conexão ssh com servidor linux.
New-SshSession -ComputerName $li_maquina  -Username $usr_maquina -Password $pw_maquina
#Teste para criação de historico
if( $historico -eq "s"){
	#Chamada da função historico.
	RelatorioHistorico
}
#Teste para opção visual.
elseif( $historico -eq "n"){
	#Pid do windows para filtro o campo pode ser vazio.
	$wpid=Read-Host "Digite o pid windows: "
	#Pid do linux para filtro o campo pode ser vazio.
	$lpid=Read-Host "Digite o pid linux: "
	#SID do oracle para filtro o campo pode ser vazio.
	$bsdi=Read-Host "Digite o SID oracle: "
	#chamada da função para apresentar o visual.
	visual
}
#Se opção digitada no historico for invalida.
else{
	#Mensagem de erro referente a função errada.
	write-host "Opção invalida"
	Read-Host "Precione enter para sair....."
}