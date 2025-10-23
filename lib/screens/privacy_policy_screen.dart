import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('隐私政策'),
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
              '隐私政策',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              '我们非常重视您的隐私。本隐私政策（以下简称"政策"）解释了我们在您使用本应用时如何收集、使用、存储和保护您的个人信息。请仔细阅读本政策，以了解我们对您个人信息的处理方式。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '1. 信息收集',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们可能会收集以下类型的个人信息：\n'
              '- 注册信息：如用户名、邮箱地址、手机号码等\n'
              '- 设备信息：如设备型号、操作系统版本、唯一设备标识符等\n'
              '- 使用数据：如应用使用频率、功能使用情况、错误日志等\n'
              '- 位置信息：如您授权我们访问您的地理位置时收集的位置数据\n'
              '- 摄像头和麦克风数据：当您使用视频通话或语音功能时，我们会请求访问您的摄像头和麦克风，以提供相关服务。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '2. 信息使用',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们收集的个人信息将用于以下目的：\n'
              '- 提供、维护和改进本应用的功能和服务\n'
              '- 验证用户身份，确保账户安全\n'
              '- 发送重要通知，如服务更新或安全警告\n'
              '- 分析用户行为，以优化用户体验\n'
              '- 遵守法律法规或响应政府机构的要求\n'
              '- 提供视频通话和语音功能：当您使用这些功能时，我们会使用您的摄像头和麦克风数据。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '3. 信息共享',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们不会将您的个人信息出售、交易或转让给第三方，除非在以下情况下：\n'
              '- 获得您的明确同意\n'
              '- 为提供您所请求的服务而必须与第三方共享\n'
              '- 遵守法律法规或响应政府机构的要求\n'
              '- 保护我们的合法权益，如防止欺诈或应对安全威胁',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '4. 信息保护',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们采取合理的技术和管理措施来保护您的个人信息，防止其被未经授权的访问、使用、披露、修改或破坏。这些措施包括但不限于：\n'
              '- 使用加密技术保护数据传输和存储\n'
              '- 定期进行安全审计和漏洞扫描\n'
              '- 限制员工和合作伙伴对个人信息的访问权限\n'
              '- 对摄像头和麦克风数据进行加密处理，确保其安全性',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '5. 信息保留',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们仅在实现本政策所述目的所需的期限内保留您的个人信息，除非法律要求或允许更长的保留期限。当个人信息不再需要时，我们将安全地删除或匿名化处理。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '6. 您的权利',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '根据相关法律法规，您享有以下权利：\n'
              '- 访问、更正或删除您的个人信息\n'
              '- 限制或反对我们对您个人信息的处理\n'
              '- 撤回您已同意的个人信息处理授权\n'
              '- 获取您的个人信息副本或将其转移至其他服务提供者\n'
              '- 随时关闭摄像头和麦克风权限，停止相关功能的使用',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '7. 政策更新',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '我们可能会不时更新本政策。更新后的政策将在本应用内公布，并立即生效。我们建议您定期查看本政策，以了解我们如何保护您的个人信息。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '8. 联系我们',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '如果您对本政策或我们的隐私实践有任何疑问，请通过以下方式联系我们：\n'
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