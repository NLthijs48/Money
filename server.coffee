db = require 'db'
plugin = require 'plugin'

getBorrowersObj = (borrowers, cents) ->
	# devide the amount, make sure it adds up to the total cents
	centsPerUser = Math.round(cents / borrowers.length)
	centsDiff = cents - centsPerUser * borrowers.length
	borrowersObj = { _MODE_: 'replace' }
	for borrowerId in borrowers
		borrowersObj[borrowerId] = centsPerUser
		if (Math.abs(centsDiff)>0)
			addCent = centsDiff/Math.abs(centsDiff)
			borrowersObj[borrowerId] += addCent
			centsDiff -= addCent
	borrowersObj

exports.client_newParticipant = (name) !->
	unique = true
	(db.shared 'dummies')? (id, n) !->
		unique = false if n is name
	return if !unique

	userId = ((db.shared 'minDummyId') || 0)-1

	db.shared "dummies #{userId}", name
	db.shared 'minDummyId', userId

exports.client_newTransaction = (values) !->
	totalCents = Math.round(parseFloat(values.amount)*100)

	borrowers = []
	for k, v of values
		if k.indexOf('pt_') is 0 and v is true
			id = 0|k.substr(3, k.length)
			borrowers.push id if id

	# TODO: check for sensible input
	return if !borrowers.length

	# create the transaction entry
	transactionId = ((db.shared 'maxTransactionId') || 0)+1
	transactionObj =
		creatorId: plugin.userId()
		lenderId: values.lenderId
		description: values.description
		cents: totalCents
		time: Math.round(Date.now()/1000)
		borrowers: getBorrowersObj borrowers, totalCents

	db.shared 'maxTransactionId', transactionId
	db.shared "transactions #{transactionId}", transactionObj

exports.client_updateTransaction = (transactionId, values) !->
	transactionObj = (db.shared "transactions #{transactionId}")
	#return if transactionObj.creatorId != plugin.userId()
	# TODO: check that the object exists, and that the current user is allowed to change
	# TODO: change borrowers and cents (only when the transaction is recent)

	borrowers = []

	# push current borrowers when they haven't been removed through this update
	(transactionObj "borrowers")? (borrowerId) !->
		borrowers.push(borrowerId) if values["pt_#{borrowerId}"] isnt false

	# now push new borrowers that were added through this update
	for k, v of values
		if k.indexOf('pt_') is 0 and v is true
			id = 0|k.substr(3, k.length)
			borrowers.push id if id and id not in borrowers
	
	return if !borrowers.length

	# write the changes
	totalCents = Math.round(parseFloat(values.amount)*100)
	transactionObj(
		lenderId: values.lenderId
		description: values.description
		cents: totalCents
		borrowers: getBorrowersObj borrowers, totalCents
	)

exports.client_delTransaction = (transactionId) !->
	# TODO: check whether deletion is allowed
	(db.shared "transactions #{transactionId}", null)

exports.onInstall = !->
	# set the counters to 0 on plugin installation
	db.shared "maxTransactionId", 0
	db.shared "minUserId", 0
