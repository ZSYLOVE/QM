import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('用户协议'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '用户协议',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              '欢迎使用本应用！在您使用本应用之前，请仔细阅读并理解本用户协议（以下简称"协议"）。本协议是您与本应用开发者之间的法律协议，规定了您使用本应用的权利和义务。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '1. 接受条款',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '通过使用本应用，您表示您已阅读、理解并同意接受本协议的所有条款和条件。如果您不同意本协议的任何条款，请立即停止使用本应用。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '2. 服务内容',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '本应用提供以下服务：\n'
              '- 用户注册与登录\n'
              '- 个人信息管理\n'
              '- 消息发送与接收\n'
              '- 其他相关功能\n'
              '我们保留随时修改、暂停或终止部分或全部服务的权利，恕不另行通知。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '3. 用户责任',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '您在使用本应用时，应遵守以下规定：\n'
              '- 不得利用本应用从事任何非法活动\n'
              '- 不得侵犯他人的知识产权或其他合法权益\n'
              '- 不得发布任何虚假、诽谤、淫秽或攻击性内容\n'
              '- 不得干扰或破坏本应用的正常运行',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '4. 隐私保护',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们非常重视您的隐私。请参阅我们的《隐私政策》以了解我们如何收集、使用和保护您的个人信息。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '5. 免责声明',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '本应用提供的服务"按原样"提供，不提供任何形式的明示或暗示的保证。我们不对以下情况承担责任：\n'
              '- 因使用或无法使用本应用而导致的任何直接或间接损失\n'
              '- 因第三方行为导致的任何损失或损害\n'
              '- 因不可抗力事件导致的服务中断或数据丢失',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '6. 协议修改',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们保留随时修改本协议的权利。修改后的协议将在本应用内公布，并立即生效。如果您继续使用本应用，即表示您接受修改后的协议。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '7. 法律适用',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '本协议的订立、执行和解释均适用中华人民共和国法律。如发生任何争议，双方应通过友好协商解决；协商不成的，任何一方均可向有管辖权的人民法院提起诉讼。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '8. 联系我们',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '如果您对本协议或本应用有任何疑问，请通过以下方式联系我们：\n'
              '邮箱：19934452063@163.com\n'
              '电话：19934452063',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
} 