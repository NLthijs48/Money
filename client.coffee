Db = require 'db'
Dom = require 'dom'
Form = require 'form'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Photo = require 'photo'
Plugin = require 'plugin'
Server = require 'server'
{tr} = require 'i18n'
Widgets = require 'widgets'

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
		Dom.text tr("Payed by %1: ", (participants (transaction 'lenderId')))
		Dom.text "€ " + ((transaction 'cents')/100).toFixed(2)
		Dom.br()

		tDate = new Date((transaction 'time') * 1000)
		Dom.small tr("on %1 (%2)", tDate.toLocaleDateString(), tDate.toLocaleTimeString())

		Dom.div !->
			Dom.style margin: '12px 0 0'
			Dom.text tr("%1 participant|s: ", borrowersCount())
		Dom.small !->
			names = []
			for borrowerId, cents of (transaction 'borrowers')()
				names.push (participants borrowerId) + " €#{(cents/100).toFixed(2)}"
			Dom.text names.join(', ')

	if (transaction 'creatorId') is curUserId
		Modal.show (transaction 'description'), !->
			modalContent()
		, (choice) !->
			Page.nav transactionId if choice is 'edit'
		, ['edit', tr("Edit"), 'ok', tr("OK")]
	else
		Modal.show (transaction 'description'), !->
			modalContent()

# the balances page shows the balances for all participants
renderBalances = !-> Dom.ul !->
	Page.setTitle tr("All balances")
	participants (participantId, participantName) !->
		isMe = +participantId is curUserId
		Dom.li !->
			Dom.style { display_: 'box', _boxAlign: 'center' }

			if participantId>0
				Dom.div !->
					Dom.style
						width: '38px'
						height: '38px'
						backgroundSize: 'cover'
						backgroundPosition: '50% 50%'
						margin: '0 4px 0 0'
						border: 'solid 2px #aaa'
						borderRadius: '36px'
					if avatar = (Plugin.users "#{participantId} public avatar")
						Dom.style backgroundImage: Photo.css(avatar)
					else
						Dom.style backgroundImage: "url(#{Plugin.resourceUri('silhouette-aaa.png')})"

			Dom.div !->
				Dom.style { _boxFlex: 1, fontWeight: if isMe then 'bold' else 'normal' }
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
	Form.pageSubmitNew (values) !->
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
			Server.call 'newParticipant', name
			Page.back()

	Dom.form !->
		Dom.p tr("Enter the name of a new participant who does not have the Happening app:")
		Form.input
			name: 'name'
			text: tr("Name")


renderNewTransaction = (id) !->
	selected = Obs.hash()

	Obs.onClean !->
		(Db.local 'lenderId', null)

	if id is 'new'
		Page.setTitle tr("New transaction")
		Form.pageSubmitNew (values) !->
			if !values.amount
				Modal.show "Please enter the amount"
			else if !values.description
				Modal.show "Please enter the description"
			else if !Obs.count(selected)
				Modal.show "Select at least one person"
			else
				log 'form values', values
				borrowers = []
				selected (borrowerId) !->
					borrowers.push(borrowerId)
				values.lenderId = lenderId()
				Server.call 'newTransaction', values, borrowers
				Page.back()

	else
		transaction = (Db.shared "transactions #{id}")
		(transaction 'borrowers') (borrowerId) !->
			(selected borrowerId, true)

		Page.setTitle tr("Edit transaction")
		Page.setActions Plugin.resourceUri('icon-trash-48.png'), !->
				Server.call 'delTransaction', id
				Page.back()
		Form.pageSubmitEdit (values) !->
			if !values.amount
				Modal.show "Please enter the amount"
			else if !values.description
				Modal.show "Please enter the description"
			else if !Obs.count(selected)
				Modal.show "Select at least one person"
			else
				log 'form values', values
				borrowers = []
				selected (borrowerId) !->
					borrowers.push(borrowerId)
				log 'borrowers ===> ', borrowers
				values = values
				values.lenderId = lenderId()
				Server.call 'updateTransaction', id, values, borrowers
				Page.back()

	lenderId = Obs.value((transaction? 'lenderId')||curUserId)
	enteredAmount = Obs.value ((transaction? 'cents')||0) / 100

	Dom.form !->
		Dom.style padding: '6px'

		Dom.div !->
			Dom.style { display_: 'box', _boxPack: 'center' }

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
						value: ((transaction? 'cents')||0) / 100
						text: tr('0.-')
						type: 'number'
						onEdit: (v) !->
							log 'setting to', v
							(enteredAmount v)
						inScope: !-> Dom.style fontSize: '100%'
				Dom.div !-> Dom.style width: '0.8em' # center the amount input

		Dom.div !->
			Dom.style
				display_: 'box'
				_boxPack: 'center'
				marginBottom: '14px'

			Dom.div !->
				Dom.style maxWidth: '14em'
				Form.input
					name: 'description'
					value: (transaction? 'description')||''
					text: 'Add a description'

		Form.sep()

		Form.box !->
			Dom.style fontSize: '125%'
			Dom.text tr("Paying person")
			Dom.div (if +lenderId() is +curUserId then tr("You") else (participants lenderId()))
			Dom.onTap !->
				Modal.show tr("Select payer"), !->
					Dom.style width: '80%'
					Dom.ol !->
						Dom.style
							maxHeight: '40%'
							overflow: 'auto'
							backgroundColor: '#eee'
							margin: '-12px -12px -15px -12px'

						participants (participantId, participantName) !->
							Dom.li !->
								if participantId > 0
									Dom.div !->
										Dom.style
											width: '38px'
											height: '38px'
											backgroundSize: 'cover'
											backgroundPosition: '50% 50%'
											margin: '0 4px 0 0'
											border: 'solid 2px #aaa'
											borderRadius: '36px'
										
										if avatar = (Plugin.users "#{participantId} public avatar")
											Dom.style backgroundImage: Photo.css(avatar)
										else
											Dom.style backgroundImage: "url(#{Plugin.resourceUri('silhouette-aaa.png')})"

								if +participantId is curUserId
									participantName = tr("You")
									Dom.style fontWeight: 'bold'
								Dom.text participantName

								Dom.div !->
									Dom.style
										padding: '0 10px'
										_boxFlex: 1
										textAlign: 'right'
										fontSize: '150%'
										color: '#72BB53'
									Dom.text (if +lenderId() is +participantId then "✓" else "")
								
								Dom.onTap !->
									(lenderId participantId)
									Modal.remove()

		Form.sep()

		Dom.div !->
			Dom.style
				display_: 'box'
				_boxAlign: 'center'
				padding: '12px 2px 0 6px'
			selectedCount = Obs.streamCount(selected)
			Dom.h2 !->
				Dom.style display: 'inline-block'
				Dom.text tr("Participants: %1", selectedCount())
			Dom.div !->
				Dom.style { _boxFlex: 1, textAlign: 'right' }
				Widgets.button tr("Clear"), !->
					participants (participantId) !->
						(selected participantId, null)
				Widgets.button tr("Select all"), !->
					participants (participantId) !->
						(selected participantId, true)

		participants (participantId, participantName) !->
			isMe = +participantId is curUserId
			Dom.section !->
				Dom.style
					display: 'inline-block'
					verticalAlign: 'top'
					margin: '6px'
					width: boxSize()-28 + 'px'
					height: '42px'

				Dom.div !->
					Dom.style { display_: 'box', _boxAlign: 'center', height: '100%' }
					if participantId > 0
						Dom.div !->
							Dom.style
								width: '38px'
								height: '38px'
								backgroundSize: 'cover'
								backgroundPosition: '50% 50%'
								margin: '0 4px 0 0'
								border: 'solid 2px #aaa'
								borderRadius: '36px'
							
							if avatar = (Plugin.users "#{participantId} public avatar")
								Dom.style backgroundImage: Photo.css(avatar)
							else
								Dom.style backgroundImage: "url(#{Plugin.resourceUri('silhouette-aaa.png')})"

					selCount = Obs.streamCount(selected)
					Dom.div !->
						Dom.style
							_boxFlex: 1
							fontWeight: if isMe then 'bold' else 'normal'
							overflow: 'hidden'
							textOverflow: 'ellipsis'

						participantName = tr("Yourself") if +participantId is curUserId
						Dom.text participantName
						if selCount() and (selected participantId) and enteredAmount()
							Dom.br()
							Dom.span !->
								Dom.style { fontWeight: 'normal', fontSize: '85%', color: 'gray' }
								Dom.text '€ ' + (Math.round(enteredAmount() / selCount() * 100) / 100).toFixed(2)

					Dom.div !->
						Dom.style { textAlign: 'right', color: '#72BB53', fontWeight: 'bold' }
						Dom.text (if (selected participantId) then "✓" else "")

				Dom.onTap !->
					if (selected "##{participantId}")
						(selected participantId, null)
					else
						(selected participantId, true)

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
	if what == 'balances'
		renderBalances()
	else if what == 'newParticipant'
		renderNewParticipant()
	else if what
		renderNewTransaction what
	else
		# main page with an overview of transactions concerning the current user
		Dom.div !->
			Dom.style { display_: 'box', margin: '6px 0', _boxAlign: 'center' }
				
			# button to trigger the balances overview page
			Widgets.bigButton !->
				Dom.style margin: 0
				Dom.text tr("All balances")
			, !-> Page.nav 'balances'

			# this user's total balance
			Dom.div !->
				Dom.style { _boxFlex: 1, textAlign: 'right', paddingRight: '14px' }
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
		Dom.ul !->
			Dom.li !->
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

				Obs.observe !-> if lentCents() or borrowedCents()
					log '>> lent, borrowed', lentCents(), borrowedCents()
					Dom.li !->
						borrowersCount = Obs.streamCount(transaction 'borrowers')

						# transaction description, amount and how many people involved
						Dom.div !->
							Dom.style
								_boxFlex: 1
							Dom.text "#{(transaction 'description')}"
							Dom.br()
							lenderName = if +(transaction 'lenderId') is curUserId then tr("you") else (Plugin.users "#{(transaction 'lenderId')} name")
							Dom.small tr("€%1 by %2 for %3 person|s", (transaction 'cents')/100, lenderName, borrowersCount())

						# balance for this transaction, for the current user
						Dom.div !->
							cents = lentCents() - borrowedCents()

							Dom.style
								textAlign: 'right'
								fontWeight: 'bold'
								color: if cents>0 then 'inherit' else '#BB5353'

							Dom.text "€ " + (cents/100).toFixed(2)

						#Dom.onTap !-> Page.nav id
						Dom.onTap !-> showTransactionModal(id)
