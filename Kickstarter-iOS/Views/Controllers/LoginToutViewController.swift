import ReactiveSwift
import Foundation
import UIKit
import MessageUI
import Library
import KsApi
import Prelude
import FBSDKLoginKit

// 登录注册界面(VC)
internal final class LoginToutViewController: UIViewController, MFMailComposeViewControllerDelegate {
  @IBOutlet fileprivate weak var contextLabel: UILabel!
  @IBOutlet fileprivate weak var bringCreativeProjectsToLifeLabel: UILabel!
  @IBOutlet fileprivate weak var fbLoginButton: UIButton!
  @IBOutlet fileprivate weak var disclaimerButton: UIButton!
  @IBOutlet fileprivate weak var loginButton: UIButton!
  @IBOutlet fileprivate weak var signupButton: UIButton!
  @IBOutlet fileprivate weak var loginContextStackView: UIStackView!
  @IBOutlet fileprivate weak var rootStackView: UIStackView!
  @IBOutlet fileprivate weak var facebookDisclaimerLabel: UILabel!

  // 这个VC用到了2个不同的viewModel
  // 这里直接用HelpViewModel()初始化，没有用单例，不会有问题吗？
  fileprivate let helpViewModel = HelpViewModel()
  private var sessionStartedObserver: Any?
  fileprivate let viewModel: LoginToutViewModelType = LoginToutViewModel()

  fileprivate lazy var fbLoginManager: FBSDKLoginManager = {
    let manager = FBSDKLoginManager()
    manager.loginBehavior = .systemAccount
    manager.defaultAudience = .friends
    return manager
  }()

  internal static func configuredWith(loginIntent intent: LoginIntent) -> LoginToutViewController {
    let vc = Storyboard.Login.instantiate(LoginToutViewController.self)
    vc.viewModel.inputs.loginIntent(intent)
    vc.helpViewModel.inputs.configureWith(helpContext: .loginTout)
    // 在这里设置了helpViewModel的input, 所以是(canSendMail)每用一次, 都要调用一次?
    vc.helpViewModel.inputs.canSendEmail(MFMailComposeViewController.canSendMail())
    return vc
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.fbLoginManager.logOut()

    self.sessionStartedObserver = NotificationCenter.default
      .addObserver(forName: .ksr_sessionStarted, object: nil, queue: nil) { [weak self] _ in
        self?.viewModel.inputs.userSessionStarted()
    }

    // 如果是present进去的VC，这个VC会有presentingViewController属性？然后可以根据这个来判断是否是present方式跳转进去的。
    if self.presentingViewController != nil {
      // 动态判断去增加，因为不是每个页面都需要这个close按钮
      // 如果不判断，从profile进去的login画面，会错误出现close按钮
      self.navigationItem.leftBarButtonItem = .close(self, selector: #selector(closeButtonPressed))
    }
    self.navigationItem.rightBarButtonItem = .help(self, selector: #selector(helpButtonPressed))

    self.disclaimerButton.addTarget(self, action: #selector(helpButtonPressed), for: .touchUpInside)
  }

  deinit {
    self.sessionStartedObserver.doIfSome(NotificationCenter.default.removeObserver)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // 可以通过判断presentingViewController属性是否为nil，来判断是否是通过present的方式进去的。
    // MARK: Inputs 5: viewWillAppear >>> view(isPresented)
    // 用于是否要以dismiss方式退出
    // 是否可以用viewWillAppear加一个Bool参数, 统一成一个input？
    self.viewModel.inputs.view(isPresented: self.presentingViewController != nil)

    // MARK: Inputs 6: viewWillAppear
    self.viewModel.inputs.viewWillAppear()
  }

  // 这个写法和bindViewModel()类似, 不过调用是在viewDidLoad后(bindViewModel()是在viewDidLoad之前)
  override func bindStyles() {
    super.bindStyles()

    // 这种写法没见过
    _ = self |> baseControllerStyle()
    _ = self.fbLoginButton |> fbLoginButtonStyle
    _ = self.disclaimerButton
      |> disclaimerButtonStyle
    _ = self.loginButton |> loginWithEmailButtonStyle
    _ = self.rootStackView
      |> loginRootStackViewStyle
      |> UIStackView.lens.spacing .~ Styles.grid(5)
    _ = self.signupButton |> signupWithEmailButtonStyle

    _ = self.facebookDisclaimerLabel |> fbDisclaimerTextStyle

    _ = self.bringCreativeProjectsToLifeLabel
      |> UILabel.lens.font %~~ { _, l in
        l.traitCollection.isRegularRegular
          ? .ksr_headline(size: 20)
          : .ksr_headline(size: 14)
      }
      |> UILabel.lens.backgroundColor .~ .white
      |> UILabel.lens.text %~ { _ in Strings.Bring_creative_projects_to_life() }

    _ = self.contextLabel
      |> UILabel.lens.backgroundColor .~ .white
      |> UILabel.lens.font %~~ { _, l in
        l.traitCollection.isRegularRegular
          ? .ksr_subhead(size: 20)
          : .ksr_subhead(size: 14)  }

    _ = self.loginContextStackView
      |> UIStackView.lens.spacing .~ Styles.gridHalf(1)
      |> UIStackView.lens.layoutMargins %~~ { _, stack in
        stack.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(10), leftRight: 0)
          : .init(top: Styles.grid(10), left: 0, bottom: Styles.grid(5), right: 0)
      }
      |> UIStackView.lens.isLayoutMarginsRelativeArrangement .~ true
    }

    override func bindViewModel() {

      // MARK: Output 1: startLogin >> pushLoginViewController
    self.viewModel.outputs.startLogin
      .observeForControllerAction()
      .observeValues { [weak self] _ in
        self?.pushLoginViewController()
    }

      // MARK: Output 2: startSignup >> pushSignupViewController
    self.viewModel.outputs.startSignup
      .observeForControllerAction()
      .observeValues { [weak self] _ in
        self?.pushSignupViewController()
    }

      // MARK: Output 2: logIntoEnvironment >> inputs.environmentLoggedIn
      // 这里的output, 又作为input传入(会影响下面的output: postNotification), 这样做的目的, 仅仅是为了减少VC的代码量吗
    self.viewModel.outputs.logIntoEnvironment
      .observeValues { [weak self] accessTokenEnv in
        AppEnvironment.login(accessTokenEnv)
        self?.viewModel.inputs.environmentLoggedIn()
    }

      // MARK: Output 3: postNotification
      // 发送两个通告: ksr_sessionStarted, ksr_showNotificationsDialog
    self.viewModel.outputs.postNotification
      .observeForUI()
      .observeValues {
        // 在viewModel组织好要发送的通告，在这里直接发送（可以在viewModel直接发送吗？放在这里发送，仅仅是为了统一？）
        NotificationCenter.default.post($0.0)
        NotificationCenter.default.post($0.1)
      }

      // MARK: Output 4: startFacebookConfirmation
    self.viewModel.outputs.startFacebookConfirmation
      .observeForControllerAction()
      .observeValues { [weak self] (user, token) in
        self?.pushFacebookConfirmationController(facebookUser: user, facebookToken: token)
    }

      // MARK: Output 5: startTwoFactorChallenge
      // 两步验证相关的内容?
    self.viewModel.outputs.startTwoFactorChallenge
      .observeForControllerAction()
      .observeValues { [weak self] token in
        self?.pushTwoFactorViewController(facebookAccessToken: token)
    }

      // MARK: Output 6: attemptFacebookLogin >> attemptFacebookLogin
      // 点击Facebook按钮的时候会调用Facebook的Login框架(然后还会有2个input进去)
    self.viewModel.outputs.attemptFacebookLogin
      .observeValues { [weak self] _ in
        self?.attemptFacebookLogin()
    }

      // MARK: Output 7: showFacebookErrorAlert
      // 弹出Facebook登录错误
    self.viewModel.outputs.showFacebookErrorAlert
      .observeForControllerAction()
      .observeValues { [weak self] error in
        self?.present(
          UIAlertController.alertController(forError: error),
          animated: true,
          completion: nil
        )
    }

      // MARK: Output 8: dismissViewController
      // userSessionStarted的时候，这个output会emit event出来
      // 而userSessionStarted的触发，是监听ksr_sessionStarted通告而触发的
    self.viewModel.outputs.dismissViewController
      .observeForControllerAction()
      .observeValues { [weak self] in
        self?.dismiss(animated: true, completion: nil)
    }

      // MARK: Output 9: showHelpSheet
      // 触发弹出HelpSheet
    self.helpViewModel.outputs.showHelpSheet
      .observeForControllerAction()
      .observeValues { [weak self] in
        // emit出来的是一个array, 里面有显示actionSheet需要的数据(5个类型)
        self?.showHelpSheet(helpTypes: $0)
    }

      // MARK: Output 10: showMailCompose
      // "canSendEmail"为true, 弹出"撰写"email的页面
    self.helpViewModel.outputs.showMailCompose
      .observeForControllerAction()
      .observeValues { [weak self] in
        guard let _self = self else { return }
        let controller = MFMailComposeViewController.support()
        controller.mailComposeDelegate = _self
        _self.present(controller, animated: true, completion: nil)
    }

      // MARK: Output 11: showNoEmailError
      // 如果手机没有设置email, "canSendEmail"为false
    self.helpViewModel.outputs.showNoEmailError
      .observeForControllerAction()
      .observeValues { [weak self] alert in
        self?.present(alert, animated: true, completion: nil)
    }

      // MARK: Output 12: showWebHelp
      // 跳到网站的, 都从这里回调出来, 参数helpType决定跳转到哪个网页
    self.helpViewModel.outputs.showWebHelp
      .observeForControllerAction()
      .observeValues { [weak self] helpType in
        self?.goToHelpType(helpType)
    }

    self.contextLabel.rac.text = self.viewModel.outputs.logInContextText
    self.bringCreativeProjectsToLifeLabel.rac.hidden = self.viewModel.outputs.headlineLabelHidden
  }

  @objc internal func mailComposeController(_ controller: MFMailComposeViewController,
                                            didFinishWith result: MFMailComposeResult,
                                            error: Error?) {
    self.helpViewModel.inputs.mailComposeCompletion(result: result)
    self.dismiss(animated: true, completion: nil)
  }

  fileprivate func goToHelpType(_ helpType: HelpType) {
    let vc = HelpWebViewController.configuredWith(helpType: helpType)
    self.navigationController?.pushViewController(vc, animated: true)
    self.navigationItem.backBarButtonItem = UIBarButtonItem.back(nil, selector: nil)
  }

  fileprivate func pushLoginViewController() {
    self.navigationController?.pushViewController(LoginViewController.instantiate(), animated: true)
    self.navigationItem.backBarButtonItem = UIBarButtonItem.back(nil, selector: nil)
  }

  fileprivate func pushTwoFactorViewController(facebookAccessToken token: String) {
    let vc = TwoFactorViewController.configuredWith(facebookAccessToken: token)
    self.navigationController?.pushViewController(vc, animated: true)
    self.navigationItem.backBarButtonItem = UIBarButtonItem.back(nil, selector: nil)
  }

  fileprivate func pushFacebookConfirmationController(facebookUser user: ErrorEnvelope.FacebookUser?,
                                                      facebookToken token: String) {
    let vc = FacebookConfirmationViewController
      .configuredWith(facebookUserEmail: user?.email ?? "", facebookAccessToken: token)
    self.navigationController?.pushViewController(vc, animated: true)
    self.navigationItem.backBarButtonItem = UIBarButtonItem.back(nil, selector: nil)
  }

  fileprivate func pushSignupViewController() {
    self.navigationController?.pushViewController(SignupViewController.instantiate(), animated: true)
    self.navigationItem.backBarButtonItem = UIBarButtonItem.back(nil, selector: nil)
  }

  fileprivate func showHelpSheet(helpTypes: [HelpType]) {
    let helpSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    helpTypes.forEach { helpType in
      helpSheet.addAction(
        UIAlertAction(title: helpType.title, style: .default) { [weak helpVM = self.helpViewModel] _ in
          helpVM?.inputs.helpTypeButtonTapped(helpType)
        }
      )
    }

    helpSheet.addAction(
      UIAlertAction(
        title: Strings.login_tout_help_sheet_cancel(),
        style: .cancel
      ) { [weak helpVM = self.helpViewModel] _ in
        helpVM?.inputs.cancelHelpSheetButtonTapped()
      }
    )

    //iPad provision
    helpSheet.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem

    self.present(helpSheet, animated: true, completion: nil)
  }

  // MARK: Facebook Login

  fileprivate func attemptFacebookLogin() {
    self.fbLoginManager
      .logIn(withReadPermissions: ["public_profile", "email", "user_friends"], from: nil) { result, error in
        if let error = error {
          self.viewModel.inputs.facebookLoginFail(error: error)
        } else if let result = result, !result.isCancelled {
          self.viewModel.inputs.facebookLoginSuccess(result: result)
        }
    }
  }

  @objc fileprivate func closeButtonPressed() {
    // 这个点击事件, 不需要viewModel进行处理, 所以不需要弄成input
    self.dismiss(animated: true, completion: nil)
  }

  @IBAction fileprivate func helpButtonPressed() {
    // MARK: Input 1: button tap - Help
    self.helpViewModel.inputs.showHelpSheetButtonTapped()
  }

  @IBAction fileprivate func facebookLoginButtonPressed(_ sender: UIButton) {
    // MARK: Input 2: button tap - Facebook
    self.viewModel.inputs.facebookLoginButtonPressed()
  }

  @IBAction fileprivate func loginButtonPressed(_ sender: UIButton) {
    // MARK: Input 3: button tap - Log in
    self.viewModel.inputs.loginButtonPressed()
  }

  @IBAction fileprivate func signupButtonPressed() {
    // MARK: Input 4: button tap - Sign up
    self.viewModel.inputs.signupButtonPressed()
  }
}

extension LoginToutViewController: TabBarControllerScrollable {
  func scrollToTop() {
    if let scrollView = self.view.subviews.first as? UIScrollView {
      scrollView.scrollToTop()
    }
  }
}
