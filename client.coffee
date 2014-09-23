Db = require 'db'
Dom = require 'dom'
Form = require 'form'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Photo = require 'photo'
Plugin = require 'plugin'
Server = require 'server'
Ui = require 'ui'
{tr} = require 'i18n'

boxSize = Obs.value()
Obs.observe !->
	width = (Dom.viewport 'width')
	cnt = (0|(width / 150)) || 1
	(boxSize (0|(width-((cnt+1)*4))/cnt))

curUserId = Plugin.userId()
	

# 'balances' is an observable containing the balances for all 
# users involved in one or more transactions
balances = Obs.hash()
(Db.shared "transactions")? (k, data) !->
	# add cents for the lender
	lenderId = (data 'lenderId')
	cents = (data 'cents')
	lenderBalance = 0|(balances "##{lenderId}")

	(balances lenderId, lenderBalance + cents)

	# subtract when this transaction is removed
	Obs.onClean !->
		(balances lenderId, (balances "##{lenderId}") - cents)

	(data 'borrowers')? (borrowerId, owedCents) !->
		# subtract cents for associated borrowers
		borrowerBalance = 0|(balances "##{borrowerId}")
		(balances borrowerId, borrowerBalance - owedCents)
		
		# add when this transaction is removed
		Obs.onClean !->
			(balances borrowerId, (balances "##{borrowerId}") + owedCents)
			
# 'participants' is an observable containing the names for all 
# Plugin.users and dummy participants
participants = Obs.hash()
Obs.observe !->
	Plugin.users (memberId, member) !->
		(participants memberId, (member 'name'))
		Obs.onClean !->
			(participants memberId, null)
	(Db.shared 'dummies')? (dummyId, dummyName) !->
		(participants dummyId, dummyName)
		Obs.onClean !->
			(participants dummyId, null)

# some logging
Obs.observe !->
	log 'transactions', (Db.shared 'transactions')?()
	log 'balances', balances?()
	log 'participants', participants?()

showTransactionModal = (transactionId) !->
	transaction = (Db.shared "transactions #{transactionId}")

	borrowersCount = Obs.streamCount(transaction 'borrowers')
	# somehow count(transaction 'borrowers') will always return 0!?

	modalContent = !->
		Dom.style textAlign: 'left'
		Dom.span !->
			Dom.style fontWeight: 'bold'
			Dom.text "€ " + ((transaction 'cents')/100).toFixed(2) + " "
			Dom.text tr("payed by %1", (participants (transaction 'lenderId')))
		Dom.br()

		tDate = new Date((transaction 'time') * 1000)
		Dom.small tr("%1 on %2", tDate.toLocaleTimeString(), tDate.toLocaleDateString())

		Dom.div !->
			Dom.style margin: '12px 0 0', fontWeight: 'bold'
			Dom.text tr("%1 participant|s", borrowersCount())
		Dom.small !->
			names = []
			for borrowerId, cents of (transaction 'borrowers')()
				Dom.div !->
					Dom.style
						display: 'inline-block'
						backgroundColor: '#bbb'
						color: '#fff'
						margin: '3px 3px 0 0'
						borderRadius: '3px'
						padding: '3px 6px'
					Dom.text (participants borrowerId)
					Dom.br()
					Dom.text "€#{(cents/100).toFixed(2)}"

	if +(transaction 'creatorId') is curUserId or +(transaction 'lenderId') is curUserId
		Modal.show (transaction 'description'), !->
			modalContent()
		, (choice) !->
			Page.nav transactionId if choice is 'edit'
		, ['edit', tr("Edit"), 'ok', tr("OK")]
	else
		Modal.show (transaction 'description'), !->
			modalContent()

# the balances page shows the balances for all participants
renderBalances = !-> Ui.list !->
	Page.setTitle tr("All balances")
	participants (participantId, participantName) !->
		isMe = +participantId is curUserId
		Ui.item !->
			Dom.style display_: 'box', _boxAlign: 'center'

			Ui.avatar Plugin.userAvatar(participantId) if participantId>0

			Dom.div !->
				Dom.style _boxFlex: 1, fontWeight: if isMe then 'bold' else 'normal'
				Dom.text participantName

			Dom.div !->
				cents = (0|(balances participantId)) / 100

				Dom.style
					textAlign: 'right'
					fontWeight: 'bold'
					color: if cents>0 then 'inherit' else '#BB5353'

				Dom.text "€ " + cents.toFixed(2)

# the page that is used to add a participant (a non happening-member)
renderNewParticipant = !->
	Page.setTitle tr("Add participant")
	Form.setPageSubmit (values) !->
		name = values.name.trim()
		if !name
			Modal.show tr("Please enter a name")
			return
		
		unique = true
		(Db.shared 'dummies')? (id, n) !->
			unique = false if n is name

		if !unique
			Modal.show tr("Name has already been used to add a participant. Please choose a different name.", name)
		else
			Server.sync 'newParticipant', name
			Page.back()

	Dom.form !->
		Dom.p tr("Enter the name of a new participant who does not have the Happening app:")
		Form.input
			name: 'name'
			text: tr("Name")
	, true


renderNewTransaction = (id) !->
	log '--- rendering new transaction!'
	selCount = Obs.value 0

	if id is 'new'
		Page.setTitle tr("New transaction")
		Form.setPageSubmit (values) !->
			if !values.amount
				Modal.show "Please enter the amount"
			else if !values.description
				Modal.show "Please enter the description"
			else if !selCount()
				Modal.show "Select at least one person"
			else
				log 'form values', values
				Server.sync 'newTransaction', values, !->
					id = ((Db.shared 'maxTransactionId')||0)+1
					Db.shared "transactions #{id}",
						creatorId: Plugin.userId()
						lenderId: values.lenderId
						description: values.description
						cents: Math.round(parseFloat(values.amount)*100)
						time: Math.round(Date.now()/1000)
						syncState: 'adding'

				Page.back()
		, true

	else
		transaction = (Db.shared "transactions #{id}")

		Page.setTitle tr("Edit transaction")
		Page.setActions
			icon: Plugin.resourceUri('icon-trash-48.png')
			action: !->
				Modal.confirm tr("Delete transaction?"), tr("Balances of affected persons will be recalculated"), !->
					Server.sync 'delTransaction', id, !->
						Db.shared "transactions #{id}",
							syncState: 'removing'
					Page.back()

		Form.setPageSubmit (values) !->
			if !values.amount
				Modal.show "Please enter the amount"
			else if !values.description
				Modal.show "Please enter the description"
			else if !selCount()
				Modal.show "Select at least one person"
			else
				log 'form values', values
				Server.sync 'updateTransaction', id, values, !->
					Db.shared "transactions #{id}",
						description: values.description
						syncState: 'updating'
				Page.back()

	lenderId = Obs.value((transaction? 'lenderId')||curUserId)
	enteredAmount = Obs.value ((transaction? 'cents')||0) / 100

	Dom.form !->
		Dom.style padding: '6px'

		Dom.div !->
			Dom.style display_: 'box', _boxPack: 'center'

			Dom.div !->
				Dom.style
					width: '4.5em'
					display_: 'box'
					fontSize: '250%'
					_boxAlign: 'center'

				Dom.div !->
					Dom.style
						width: '0.8em'
						padding: '0 0 4px'
						textAlign: 'center'
						color: 'gray'
					Dom.text '€'
				Dom.div !->
					Dom.style _boxFlex: 1
					Form.input
						name: 'amount'
						value: (if transaction then (transaction? 'cents') / 100 else null)
						text: tr('0.-')
						type: 'number'
						onChange: (v) !->
							(enteredAmount v)
						inScope: !-> Dom.style fontSize: '100%'
				Dom.div !-> Dom.style width: '0.8em' # center the amount input

		Dom.div !->
			Dom.style display_: 'box', _boxPack: 'center', marginBottom: '14px'

			Dom.div !->
				Dom.style maxWidth: '14em'
				Form.input
					name: 'description'
					value: (transaction? 'description')||''
					text: 'Add a description'

		Form.sep()

		# input that handles selection of the paying person
		selectPayer = (opts) !->
			[handleChange, initValue] = Form.makeInput opts, (v) -> 0|v

			value = Obs.value initValue
			Form.box !->
				opts.content? value()

				Dom.onTap !->
					Modal.show opts.optionsTitle, !->
						Dom.style width: '80%'
						Ui.list !->
							Dom.style
								maxHeight: '40%'
								overflow: 'auto'
								_overflowScrolling: 'touch'
								backgroundColor: '#eee'
								margin: '-12px -12px -15px -12px'

							options = opts.options?() or opts.options
							for optionId, optionName of options
								Ui.item !->
									chosenId = optionId # bind to this scope
									opts.optionContent? chosenId, optionName, (+value() is +chosenId)
									
									Dom.onTap !->
										value chosenId
										handleChange value()
										Modal.remove()


		# render selection of paying person
		selectPayer
			name: 'lenderId'
			value: (transaction? 'lenderId')||curUserId
			options: participants
			optionsTitle: tr("Change paying person")
			optionContent: (optionId, optionName, isChosen) !->
				log "option #{optionId} #{optionName} #{isChosen}"
				Ui.avatar Plugin.userAvatar(optionId) if optionId>0

				if +optionId is curUserId
					optionName = tr("You")
					Dom.style fontWeight: 'bold'
				Dom.text optionName

				Dom.div !->
					Dom.style
						padding: '0 10px'
						_boxFlex: 1
						textAlign: 'right'
						fontSize: '150%'
						color: '#72BB53'
					Dom.text (if isChosen then "✓" else "")
			content: (value) !->
				Dom.style fontSize: '125%'
				Dom.text tr("Payed by %1", (if +value is +curUserId then tr("you") else (participants value)))
				Dom.div tr("Tap to change")


		Form.sep()

		participantToggles = {}
		selCount = Obs.value 0

		Dom.div !->
			Dom.style
				display_: 'box'
				_boxAlign: 'center'
				padding: '12px 2px 0 6px'
			Dom.h2 !->
				Dom.style display: 'inline-block'
				Dom.text tr("Participants: %1", selCount())
			Dom.div !->
				Dom.style _boxFlex: 1, textAlign: 'right'
				Ui.button tr("Clear"), !->
					participants (participantId) !->
						participantToggles[participantId]?.value false
				Ui.button tr("Select all"), !->
					participants (participantId) !->
						participantToggles[participantId]?.value true

		# input that handles selection of the participants
		participantToggle = (opts) ->
			[handleChange, initValue] = Form.makeInput opts, (v) -> !!v

			value = Obs.value initValue
			Dom.section !->
				Dom.style
					display: 'inline-block'
					verticalAlign: 'top'
					margin: '6px'
					width: boxSize()-28 + 'px'
					height: '42px'

				opts.content? value()

				Dom.onTap !->
					value !value()
					handleChange value()

			value: (arg) !->
				if arg is undefined
					return value()
				value !!arg
				handleChange !!arg


		# create participantToggles for each participant
		participants (participantId, participantName) !->
			participantToggles[participantId] = participantToggle
				name: 'pt_'+participantId
				value: !!(transaction? "borrowers #{participantId}")
				content: (value) !->
					if value
						selCount selCount()+1
						Obs.onClean !->
							selCount selCount()-1

					Dom.div !->
						Dom.style display_: 'box', _boxAlign: 'center', height: '100%'
						Ui.avatar Plugin.userAvatar(participantId) if participantId > 0

						Dom.div !->
							Dom.style
								_boxFlex: 1
								fontWeight: if +participantId is curUserId then 'bold' else 'normal'
								overflow: 'hidden'
								textOverflow: 'ellipsis'

							participantName = tr("Yourself") if +participantId is curUserId
							Dom.text participantName
							if selCount() and value and enteredAmount()
								Dom.br()
								Dom.span !->
									Dom.style fontWeight: 'normal', fontSize: '85%', color: 'gray'
									Dom.text '€ ' + (Math.round(enteredAmount() / selCount() * 100) / 100).toFixed(2)

						Dom.div !->
							Dom.style textAlign: 'right', color: '#72BB53', fontWeight: 'bold'
							Dom.text (if value then "✓" else "")


		Dom.section !->
			Dom.style
				display: 'inline-block'
				color: '#72bb53'
				verticalAlign: 'top'
				margin: '6px'
				width: boxSize()-30 + 'px'
				textAlign: 'center'
				lineHeight: '42px'
				height: '42px'
				overflow: 'hidden'
				textOverflow: 'ellipsis'

			Dom.text tr("+ New participant")
			Dom.onTap !-> Page.nav 'newParticipant'


exports.render = !->
	what = (Page.state 0)
	log '--- what', what
	if what == 'balances'
		renderBalances()
	else if what == 'newParticipant'
		renderNewParticipant()
	else if what
		renderNewTransaction what
	else
		# main page with an overview of transactions concerning the current user
		Dom.div !->
			Dom.style display_: 'box', margin: '6px 0', _boxAlign: 'center'
				
			# button to trigger the balances overview page
			Ui.bigButton !->
				Dom.style margin: 0
				Dom.text tr("All balances")
			, !-> Page.nav 'balances'

			# this user's total balance
			Dom.div !->
				Dom.style  _boxFlex: 1, textAlign: 'right', paddingRight: '14px'
				Dom.span !->
					Dom.style fontSize: '85%'
					Dom.text "Your balance:"
				Dom.br()
				Dom.span !->
					euros = ((balances curUserId)||0)/100
					Dom.style
						fontWeight: 'bold'
						fontSize: '125%'
						color: if euros>0 then 'inherit' else '#BB5353'
					Dom.text "€ " + euros.toFixed(2)

		# display an overview of transactions where the current user is involved
		Ui.list !->
			Ui.item !->
				Dom.style color: '#72bb53'
				Dom.text tr('+ New transaction')
				Dom.onTap !-> Page.nav 'new'

			(Db.shared 'transactions')? (id, transaction) !->
				borrowedCents = Obs.value(0)
				lentCents = Obs.value(0)

				Obs.observe !->
					(lentCents (transaction 'cents')) if +(transaction 'lenderId') is curUserId
					(transaction 'borrowers')? (borrowerId, cents) !-> if +borrowerId is curUserId
						(borrowedCents cents)
						Obs.onClean !->
							(borrowedCents 0)

				Obs.observe !-> if lentCents() or borrowedCents() or +(transaction 'creatorId') is curUserId
					log '>> lent, borrowed', lentCents(), borrowedCents()
					Ui.item !->
						syncText = false
						if ss=(transaction 'syncState')
							if ss is 'updating'
								syncText = tr("Updating transaction...")
							else if ss is 'removing'
								syncText = tr("Removing transaction...")
							else
								syncText = tr("Adding transaction...")
						else
							borrowersCount = Obs.streamCount(transaction 'borrowers')

						# transaction description, amount and how many people involved
						Dom.div !->
							Dom.style _boxFlex: 1
							Dom.text "#{(transaction 'description')}"
							Dom.br()
							if syncText
								Dom.small syncText
							else
								lenderName = if +(transaction 'lenderId') is curUserId then tr("you") else Plugin.userName(transaction 'lenderId')
								Dom.small tr("€%1 by %2 for %3 person|s", (transaction 'cents')/100, lenderName, borrowersCount())

						# balance for this transaction, for the current user
						Dom.div !->
							if syncText
								Ui.spinner 24
							else
								cents = lentCents() - borrowedCents()
								Dom.style
									textAlign: 'right'
									fontWeight: 'bold'
									color: if cents>0 then 'inherit' else '#BB5353'

								Dom.text "€ " + (cents/100).toFixed(2)

						#Dom.onTap !-> Page.nav id
						if !syncText
							Dom.onTap !-> showTransactionModal(id)
			, (id) -> -id
