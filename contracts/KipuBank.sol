//SPDX-License-Identifier: MIT

pragma solidity  > 0.8.26;

/*Objetivos del examen

Aplicar conceptos básicos de Solidity aprendidos en clase.
Seguir patrones de seguridad.
Usar comentarios y una estructura limpia para mejorar la legibilidad y el mantenimiento del contrato.
Desplegar un contrato inteligente completamente funcional en una testnet.
Crear un repositorio de GitHub que documente y muestre tu proyecto.
Descripción y requisitos de la tarea

Tu tarea es recrear el contrato inteligente KipuBank con funcionalidad completa y documentación, según se describe a continuación.

Características de KipuBank:


Usar errores personalizados en lugar de require strings.
Respetar el patrón checks-effects-interactions y las convenciones de nombres.
Usar modificadores cuando sea apropiado para validar la lógica.
Manejar transferencias nativas de forma segura.
Mantener las variables de estado limpias, legibles y bien comentadas.
Agregar comentarios NatSpec para cada función, error y variable de estado.
Aplicar convenciones de nombres adecuadas.
*/



/**
	*@title Contrato KipuBank
	*@notice Este es un contrato con fines educativos.
	*@author Miosio
	*@custom:security No usar en producción.
*/

contract KipuBank {

/*///////////////////////
					Variables
	///////////////////////*/
	
	
	///@notice mapping para almacenar el valor de los clientes 
	mapping(address client => uint256 amount) public balances;
	
    ///@notice mapping para almacenar el valor del cliente 
    uint256 public immutable WITHDRAW_MAX;

    ///@notice Limite maximo de transferencias
    uint256 public bankCap;
    ///@notice Contador de transacciones
    uint256 public transactionsCounter;
    ///@notice contador de extracciones
    uint256 public withdrawalCounter;

	/*///////////////////////
						Events
	////////////////////////*/
	///@notice evento emitido cuando se realiza un nuevo deposito 
	event depositDone(address client, uint256 amount);
	///@notice evento emitido cuando se realiza un retiro
	event withdrawalDone(address client, uint256 amount);
	
	/*///////////////////////
						Errors
	///////////////////////*/
	///@notice error emitido cuando falla una transacción
	error transactionFailed();
    	///@notice error emitido cuando quiere retirar fondos insuficientes
    error insufficientBalance(uint256 have, uint256 need);
    ///@notice error emitido cuando quiere retirar mas fondos idel total
    error capExceeded(uint256 requested, uint256 cap);
	///@notice error emitido cuando una dirección diferente al beneficiario intenta retirar
	error wrongUser(address thief, address victim);
    ///@notice error emitido cuando se ahce una transferencia de 0 wei
    error zeroDeposit();
    /*///////////////////////
					Functions
	///////////////////*/
    constructor(uint256 capWei, uint256 maxTransactions) {
        require(capWei > 0, "cap = 0");
        WITHDRAW_MAX = capWei; // asignacion unica (inmutable)
        require(maxTransactions > 0, "At least 1 transaction");
        bankCap = maxTransactions;
    }

    
    /**
		*@notice función para depositar
		*@dev esta función debe sumar el valor transferiado a la cuenta del usuario a su balance actual
		*@dev esta función debe emitir un evento informando la transaccion 
	*/
	function deposit() external payable {
        _depostiRequierements(msg.value);
		balances[msg.sender] = balances[msg.sender] += msg.value;
        unchecked{
        transactionsCounter = transactionsCounter + 1;
        }
		emit depositDone(msg.sender, msg.value);
	}
    /**
		*@notice función para retirar
		*@dev esta función debe restar el valor solicitado a la cuenta del usuario a su balance actual
		*@dev esta función debe emitir un evento informando la transaccion 
	*/
    function withdrawal(uint256 value) external payable {
        _withdrawlRequierements(value, WITHDRAW_MAX, balances[msg.sender]);

        balances[msg.sender] = balances[msg.sender] - value;
        (bool ok, ) = msg.sender.call{value: value}("");
        if(!ok)revert transactionFailed();
        unchecked{
        withdrawalCounter = withdrawalCounter + 1;
        }
        emit withdrawalDone(msg.sender,value);
    }
    /**
		*@notice función para ver el estado de las transacciones
		*@dev esta función devuelve los depitos y retiros hechos
	*/
    function bankStats()external view returns ( uint256 totalDeposits, uint256 totalwithdrawal) {
        
        totalDeposits = transactionsCounter;
        totalwithdrawal = withdrawalCounter;
    }
    /**
		*@notice función pprivate que valida previemnte al deposito
		*@dev esta función verifica que el deposito no sea 0 y que no se halla excedido el limite de trasacciones del banco
	*/
    function _depostiRequierements(uint256 value) private view {
        if (value == 0) revert zeroDeposit();
        if (transactionsCounter >= bankCap) revert capExceeded(transactionsCounter, bankCap);
    }
    /**
		*@notice función pprivate que valida previemnte al retiro
		*@dev esta función verifica que tenga fondos y no exceda el monto maximo de retiro
	*/
    function _withdrawlRequierements(uint256 value, uint256 cap, uint256 balance) private pure {
        if (value > cap) revert capExceeded(value, cap);
        if (value > balance) revert insufficientBalance(balance, value);
    }
}