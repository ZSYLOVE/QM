import 'package:flutter/material.dart';
import 'package:onlin/servers/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phonenumController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscureText = true;

  void _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    String username = usernameController.text;
    String email = emailController.text;
    String phonenumber = phonenumController.text;
    String password = passwordController.text;

    ApiService apiService = ApiService();
    bool success = await apiService.register(username, email, phonenumber, password);

    setState(() {
      isLoading = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册成功')),
      );

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
        arguments: email,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.blue[50]!,
              Colors.purple[50]!,
              Colors.pink[50]!,
            ],
            stops: [0.0, 0.4, 0.7, 1.0],
          ),
        ),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.people_alt_sharp, size: 100, color: Colors.blue[200]),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: usernameController,
                          keyboardType: TextInputType.name,
                          decoration: _buildInputDecoration('用户名', Icons.person_2_rounded),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return '请输入用户名';
                            if (value.length < 2) return '用户名太短';
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _buildInputDecoration('邮箱', Icons.email_rounded),
                          validator: (value) {
                            if (value == null || value.isEmpty) return '请输入邮箱';
                            final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                            if (!emailRegex.hasMatch(value)) return '邮箱格式不正确';
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: phonenumController,
                          keyboardType: TextInputType.phone,
                          decoration: _buildInputDecoration('手机号', Icons.phone_rounded),
                          validator: (value) {
                            if (value == null || value.isEmpty) return '请输入手机号';
                            if (!RegExp(r'^\d{11}$').hasMatch(value)) return '手机号格式应为11位数字';
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: passwordController,
                          obscureText: _obscureText,
                          keyboardType: TextInputType.visiblePassword,
                          decoration: _buildInputDecoration('密码', Icons.password_rounded).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureText ? Icons.visibility_off : Icons.visibility,
                                color: Colors.blue[200],
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureText = !_obscureText;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return '请输入密码';
                            if (value.length < 6) return '密码至少6位';
                            return null;
                          },
                        ),
                        SizedBox(height: 30),
                        isLoading
                            ? CircularProgressIndicator(color: Colors.blue[200])
                            : ElevatedButton(
                                onPressed: _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[200],
                                  padding: EdgeInsets.symmetric(vertical: 15, horizontal: 100),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  '注册',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.blue[200]),
      filled: true,
      fillColor: Colors.white.withOpacity(0.8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
    );
  }
}
