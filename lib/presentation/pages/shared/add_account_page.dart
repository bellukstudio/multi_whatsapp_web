import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/account/account_bloc.dart';

/// PRD §7 Add WhatsApp Account.
///
/// Note: the QR code itself is rendered by web.whatsapp.com *inside* the
/// isolated WebView once navigation happens — this screen only collects
/// the account's display name, then the caller creates the account +
/// activates its session (see SessionCubit.switchTo), after which the
/// WebViewContainer shows the live QR.
class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key});

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AccountBloc>().add(AccountAdded(_controller.text));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  hintText: 'e.g. Personal, Business, Sales',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _submit, child: const Text('Continue to QR scan')),
              const SizedBox(height: 8),
              const Text(
                'On the next screen, scan the QR code with WhatsApp on your '
                'phone (Linked Devices) to connect this account.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
