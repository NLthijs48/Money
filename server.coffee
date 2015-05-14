Db = require 'db'
Plugin = require 'plugin'

exports.client_transaction = (id, data) !->
	if !id
		id = Db.shared.modify 'transactionId', (v) -> (v||0)+1
	else
		prevData = Db.shared.get 'transactions', id
		# undo previous data on balance
		balanceAmong -prevData.total, prevData.by
		balanceAmong prevData.total, prevData.for	
	
	data.total = +data.total
	
	Db.shared.set 'transactions', id, data
	
	balanceAmong data.total, data.by
	balanceAmong -data.total, data.for
	
balanceAmong = (total, users) !->
	
	divide = []
	remain = total
	for userId,amount of users
		if amount is true
			divide.push userId
		else
			amount = Math.round(+amount*100)*.01
			remain -= amount
			Db.shared.modify 'balances', userId, (v) -> (v||0) + amount
			
	if remain
		amount = Math.round(remain / divide.length) # divide by zero when input data does not add up
		while userId = divide.pop()
			Db.shared.modify 'balances', userId, (v) -> (v||0) + amount
			remain -= amount
			
		if remain
			# random user gets (un)lucky
			count = 0
			for userId of users
				if Math.random() < 1/++count
					luckyId = userId
			Db.shared.modify 'balances', luckyId, (v) -> (v||0) + remain

exports.client_settleStart = !->
	Plugin.assertAdmin()
	# TODO: multi-party division
	Db.shared.set 'settle', '1:2', {done: 0, amount: 123}

exports.client_settleStop = !->
	Plugin.assertAdmin()
	Db.shared.remove 'settle'
	
exports.client_settlePayed = (key) !->
	[from,to] = key.split(':')
	return if Plugin.userId() != +from
	Db.shared.modify 'settle', key, 'done', (v) -> (v&~1) | ((v^1)&1)

exports.client_settleDone = (key) !->
	amount = Db.shared.get 'settle', key, 'amount'
	[from,to] = key.split(':')
	return if !amount? or Plugin.userId() != +to
	done = Db.shared.modify 'settle', key, 'done', (v) -> (v&~2) | ((v^2)&2)
	amount = -amount if !(done&2)
	Db.shared.modify 'balances', from, (v) -> (v||0) + amount
	Db.shared.modify 'balances', to, (v) -> (v||0) - amount
	
exports.client_account = (text) !->
	Db.shared.set 'accounts', Plugin.userId(), text