use ironrdp_core::impl_as_any;
use ironrdp_pdu::PduResult;
use ironrdp_pdu::gcc::ChannelName;
use ironrdp_svc::{CompressionCondition, SvcClientProcessor, SvcMessage, SvcProcessor};

#[derive(Debug, Default)]
pub struct NoopRdpSnd;

impl_as_any!(NoopRdpSnd);

impl SvcProcessor for NoopRdpSnd {
    fn channel_name(&self) -> ChannelName {
        ChannelName::from_static(b"rdpsnd\0\0")
    }

    fn compression_condition(&self) -> CompressionCondition {
        CompressionCondition::Never
    }

    fn process(&mut self, payload: &[u8]) -> PduResult<Vec<SvcMessage>> {
        println!(
            "[portix_rdp][DEBUG] NoopRdpSnd::process called: payload_len={}",
            payload.len()
        );
        Ok(Vec::new())
    }
}

impl SvcClientProcessor for NoopRdpSnd {}
